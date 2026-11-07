// 画面確認用の「にせSupabase」（本番では使いません）。dev/check-mobile.js から読み込みます。
// localStorage: stub_logged=1（ログイン済み） / stub_member=1（会員登録済み） / stub_role=teacher|student
(function(){
const QS=window.__STUB_QUESTIONS__||[];
const ls=k=>localStorage.getItem(k);
const uid="u1",now=Date.now(),iso=t=>new Date(t).toISOString();
const db={
  l2_members: ls("stub_member")?[{id:uid,nickname:"テスト受講者（長めのニックネーム）",full_name:"見本 花子",email:"me@example.com",role:ls("stub_role")||"student",created_at:iso(now)}]:[],
  l2_exams:[{id:"ex0",user_id:uid,subject:"財務分析",include_hard:true,question_count:33,started_at:iso(now-86400000),finished_at:iso(now-86000000)}],
  l2_answers:QS.filter(q=>q.subject==="財務分析").slice(0,12).map((q,i)=>({id:i+1,exam_id:"ex0",user_id:uid,question_id:q.id,choice:i%3!==0,is_correct:i%3!==0,time_ms:15000+i*2500,answered_at:iso(now-86000000)}))
};
if(ls("stub_role")==="teacher"){db.l2_members.push({id:"u2",nickname:"受講者B",full_name:"見本 太郎",email:"b@example.com",role:"student",created_at:iso(now)});
  QS.slice(0,30).forEach((q,i)=>db.l2_answers.push({id:100+i,exam_id:"exB",user_id:"u2",question_id:q.id,choice:true,is_correct:i%4!==0,time_ms:20000+i*900,answered_at:iso(now)}));
  db.l2_exams.push({id:"exB",user_id:"u2",subject:null,include_hard:false,question_count:64,started_at:iso(now),finished_at:iso(now)});}
let seq=1000;
function qb(t){let f=[],op="select",payload=null;const rows=()=>db[t].filter(r=>f.every(g=>g(r)));const api={
  select(){return api},order(){return api},eq(k,v){f.push(r=>r[k]===v);return api},not(k,o,v){f.push(r=>r[k]!=null);return api},
  range(a,b){return Promise.resolve({data:rows().slice(a,b+1),error:null})},
  maybeSingle(){return Promise.resolve({data:rows()[0]||null,error:null})},
  single(){if(op==="insert"){const r={role:"student",created_at:iso(Date.now()),...payload};db[t].push(r);localStorage.setItem("stub_member","1");return Promise.resolve({data:r,error:null})}
    if(op==="update")rows().forEach(r=>Object.assign(r,payload));return api.maybeSingle()},
  insert(p){op="insert";payload=p;return api},update(p){op="update";payload=p;return api},
  then(res){if(op==="update")rows().forEach(r=>Object.assign(r,payload));res({data:rows(),error:null})}};return api}
let cur=null;
window.supabase={createClient:()=>({
  auth:{getSession:async()=>({data:{session:ls("stub_logged")?{user:{id:uid,email:"me@example.com",user_metadata:{full_name:"見本 花子"}}}:null}}),onAuthStateChange(){},
    signInWithPassword:async()=>{localStorage.setItem("stub_logged","1");location.reload();return {data:{},error:null}},
    signOut:async()=>{localStorage.removeItem("stub_logged");location.reload()},signUp:async()=>({data:{session:null},error:null}),signInWithOAuth:async()=>({error:null})},
  from:qb,
  rpc:async(name,a)=>{
    const strip=({answer,explanation,...r})=>r;
    if(name==="l2_question_list")return {data:QS.map(strip),error:null};
    if(name==="l2_question_stats"){const g={};db.l2_answers.forEach(x=>{(g[x.question_id]=g[x.question_id]||[]).push(x)});
      return {data:Object.entries(g).map(([k,v])=>({question_id:k,n:v.length,accuracy:v.filter(x=>x.is_correct).length/v.length,median_ms:v[v.length>>1].time_ms})),error:null}}
    if(name==="l2_start_exam"){const pool=QS.filter(q=>(!a.p_subject||q.subject===a.p_subject)&&(a.p_include_hard||q.level==="標準"));
      cur={id:"ex"+(seq++),user_id:uid,subject:a.p_subject,include_hard:a.p_include_hard,question_count:pool.length,started_at:iso(Date.now()),finished_at:null};db.l2_exams.unshift(cur);
      return {data:pool.map(q=>({exam_id:cur.id,...strip(q)})),error:null}}
    if(name==="l2_submit_answer"){const q=QS.find(x=>x.id===a.p_question);
      db.l2_answers.push({id:seq++,exam_id:a.p_exam,user_id:uid,question_id:q.id,choice:a.p_choice,is_correct:a.p_choice===q.answer,time_ms:a.p_time_ms,answered_at:iso(Date.now())});return {data:true,error:null}}
    if(name==="l2_finish_exam"||name==="l2_review"){const e=db.l2_exams.find(x=>x.id===a.p_exam);if(e&&!e.finished_at)e.finished_at=iso(Date.now());
      return {data:db.l2_answers.filter(x=>x.exam_id===a.p_exam).map(x=>{const q=QS.find(y=>y.id===x.question_id);return {question_id:x.question_id,choice:x.choice,is_correct:x.is_correct,time_ms:x.time_ms,answer:q.answer,explanation:q.explanation}}),error:null}}
    return {data:null,error:{message:"unknown rpc "+name}};
  }
})};
})();
