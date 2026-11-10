// 対戦エンジンだけ取り出してランダム対戦を回す
const fs = require('fs'), vm = require('vm');
const src = fs.readFileSync(process.argv[2] || '/home/user/megapoke/megapoke.html', 'utf8');
const a = src.indexOf('const CARDS = {'), b = src.indexOf('/* ================= Supabase room plumbing');
const stub = new Proxy(function(){}, { get: (t, k) => k === Symbol.toPrimitive ? () => '' : stub, apply: () => stub, construct: () => stub });
const ctx = { document: stub, window: stub, localStorage: { getItem: () => null, setItem(){}, removeItem(){} }, sessionStorage: { getItem: () => 'x', setItem(){}, removeItem(){} }, navigator: stub, sb: null, ROOM_PLAYER_NAMES: {}, STATUS_LABEL: { poison:'どく', burn:'やけど', paralysis:'まひ', sleep:'ねむり', confusion:'こんらん' }, console, Math, setTimeout(){}, crypto: stub, location: stub };
vm.createContext(ctx);
vm.runInContext(src.slice(a, b) + '\n;Object.assign(globalThis,{CARDS,newGameState,shuffle,placeSetupBasic,canPlaceSetupBasic,markSetupReady,canPlayBasic,playBasic,canAttachEnergy,attachEnergy,canKaika,doKaika,canPlayTrainer,playTrainer,canPlayTool,attachTool,canUseAbility,useAbility,canRetreat,doRetreat,doPromote,canAttack,doAttack,endTurn,getEffectiveAttacks,canPayCost,effectiveRetreatCost});', ctx);
const G = ctx, C = G.CARDS, R = n => Math.floor(Math.random() * n), pick = a => a[R(a.length)];
const ids = Object.keys(C);
const basics = ids.filter(i => C[i].kind === 'creature' && C[i].basic);
function randDeck(){ const d = []; for(let i = 0; i < 4; i++) d.push(pick(basics)); for(let i = 0; i < 16; i++) d.push(pick(ids)); return G.shuffle(d); }
const issues = {}; const note = (k, x) => { (issues[k] = issues[k] || { n: 0, ex: x }).n++; };
function check(s, where){
  for(const sl of ['p1','p2']){ const p = s.players[sl];
    if(p.bench.length > 3) note('bench>3', where);
    for(const f of [p.active, ...p.bench].filter(Boolean)){
      if(f.hp !== f.maxHp - f.damage && !(f.hp === 0 && f.damage >= f.maxHp)) note('hp!=maxHp-damage', where + ' ' + C[f.cardId].name + ` hp${f.hp} max${f.maxHp} dmg${f.damage}`);
      if(f.hp < 0 || f.hp > f.maxHp) note('hp範囲外', where);
      if(f.hp <= 0 && s.phase !== 'finished') note('HP0のまま場に残る', where + ' ' + C[f.cardId].name);
    }
    if(p.points > 4) note('points>4', where);
  }
}
let stats = { games: 0, finished: 0, stuck: 0, turns: 0 };
for(let g = 0; g < (+process.argv[3] || 3000); g++){
  let s, where = 'init';
  try{
    s = G.newGameState(randDeck(), randDeck(), [pick(['格闘','悪','超'])], null);
    for(const sl of ['p1','p2']){ const p = s.players[sl]; let guard = 0;
      while(guard++ < 8){ const c = p.hand.filter(id => G.canPlaceSetupBasic(s, sl, id)); if(!c.length || (p.active && R(3) === 0)) break; G.placeSetupBasic(s, sl, pick(c)); }
      if(!p.active){ note('初手にたね無し', ''); } }
    if(!s.players.p1.active || !s.players.p2.active) continue;
    G.markSetupReady(s, 'p1'); G.markSetupReady(s, 'p2');
    stats.games++;
    let t = 0;
    while(s.phase === 'playing' && t++ < 400){
      const sl = s.activePlayer, p = s.players[sl], o = s.players[sl === 'p1' ? 'p2' : 'p1'];
      const before = [o.active, ...o.bench].filter(Boolean).map(f => [f, f.damage, C[f.cardId]]);
      where = 'promote'; if(!p.active && p.bench.length) G.doPromote(s, sl, R(p.bench.length));
      for(let k = 0; k < 12 && s.phase === 'playing'; k++){
        const acts = [];
        p.hand.forEach(id => { if(G.canPlayBasic(s, sl, id)) acts.push(['basic', id]); if(G.canKaika(s, sl, id)) acts.push(['kaika', id]); if(G.canPlayTrainer(s, sl, id)) acts.push(['trainer', id]); if(G.canPlayTool(s, sl, id)) acts.push(['tool', id]); });
        if(G.canAttachEnergy(s, sl)) acts.push(['energy']);
        if(G.canUseAbility(s, sl)) acts.push(['ability']);
        p.bench.forEach((b, i) => { if(p.active && G.canRetreat(s, sl, i)) acts.push(['retreat', i]); });
        if(!acts.length || R(5) === 0) break;
        const [k2, x] = pick(acts); where = k2 + ' ' + (C[x] ? C[x].name : x ?? '');
        const tgt = () => (p.bench.length && R(2)) ? { where: 'bench', idx: R(p.bench.length) } : { where: 'active' };
        if(k2 === 'basic') G.playBasic(s, sl, x); else if(k2 === 'kaika') G.doKaika(s, sl, x);
        else if(k2 === 'trainer') G.playTrainer(s, sl, x); else if(k2 === 'tool') G.attachTool(s, sl, x, p.active ? tgt() : { where: 'bench', idx: 0 });
        else if(k2 === 'energy') G.attachEnergy(s, sl, p.active ? tgt() : { where: 'bench', idx: 0 });
        else if(k2 === 'ability') G.useAbility(s, sl, tgt()); else if(k2 === 'retreat') G.doRetreat(s, sl, x);
        check(s, where);
      }
      if(s.phase !== 'playing') break;
      const atks = p.active ? G.getEffectiveAttacks(p.active).map((x, i) => i).filter(i => G.canAttack(s, sl, i)) : [];
      if(atks.length && R(6)){
        const i = pick(atks), atk = G.getEffectiveAttacks(p.active)[i]; where = 'attack ' + C[p.active.cardId].name + '/' + atk.name;
        const defBefore = o.active, d0 = o.active ? o.active.damage : 0, atkCard = C[p.active.cardId];
        G.doAttack(s, sl, i, R(3));
        if(defBefore && atk.dmg === 0 && !atk.coin && !atk.coinKO && defBefore.damage > d0) note('ダメージ0のワザでダメージ', where + ' → ' + C[defBefore.cardId].name + ' +' + (defBefore.damage - d0));
        check(s, where);
      }
      if(s.phase === 'playing'){ where = 'endTurn'; G.endTurn(s); check(s, where); }
    }
    stats.turns += t;
    if(s.phase === 'finished') stats.finished++; else { stats.stuck++; const n = sl => { const p = s.players[sl]; return (p.active ? 1 : 0) + p.bench.length; }; note('決着つかず(400ターン)', `場の数 p1=${n('p1')} p2=${n('p2')} 点 ${s.players.p1.points}-${s.players.p2.points}`); }
  }catch(e){ note('例外: ' + e.message.slice(0, 60), where); }
}
console.log(JSON.stringify(stats)); for(const [k, v] of Object.entries(issues)) console.log(`${v.n}件  ${k}  例: ${v.ex}`);
