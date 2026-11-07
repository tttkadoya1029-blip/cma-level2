// スマホ・PCでの表示確認スクリプト
// 使い方: node dev/check-mobile.js → dev/screens/ に画面ごとのスクリーンショットを保存
// にせSupabase（dev/stub-supabase.js）で全画面を操作し、横はみ出し・JSエラーを検出します。
const {chromium}=require("playwright");
const fs=require("fs"),path=require("path"),http=require("http");
const ROOT=path.join(__dirname,".."),OUT=path.join(__dirname,"screens");
fs.mkdirSync(OUT,{recursive:true});
const VIEWPORTS=[{name:"iphone-se",width:375,height:667},{name:"iphone-15",width:393,height:852},{name:"android-small",width:360,height:740},{name:"pc",width:1280,height:900}];
const QJSON=fs.readFileSync(path.join(ROOT,"tools","questions.json"),"utf8");

const server=http.createServer((req,res)=>{
  let p=req.url.split("?")[0];if(p==="/")p="/index.html";
  if(p==="/index.html"){
    const html=fs.readFileSync(path.join(ROOT,"index.html"),"utf8")
      .replace('<script src="config.js"></script>',`<script>window.APP_CONFIG={SUPABASE_URL:"https://stub.supabase.co",SUPABASE_ANON_KEY:"stub",ENABLE_GOOGLE:true};window.__STUB_QUESTIONS__=${QJSON}</script>`)
      .replace(/<script src="https:\/\/cdn\.jsdelivr[^>]*><\/script>/,'<script src="/dev/stub-supabase.js"></script>');
    res.setHeader("content-type","text/html; charset=utf-8");return res.end(html);
  }
  try{res.end(fs.readFileSync(path.join(ROOT,p)))}catch{res.statusCode=404;res.end()}
}).listen(0);
const URL_=`http://localhost:${server.address().port}/`;

(async()=>{
  const browser=await chromium.launch();const problems=[];
  for(const vp of VIEWPORTS){
    for(const role of ["student","teacher"]){
      const ctx=await browser.newContext({viewport:{width:vp.width,height:vp.height},deviceScaleFactor:vp.name==="pc"?1:2,isMobile:vp.name!=="pc",hasTouch:vp.name!=="pc"});
      const page=await ctx.newPage();
      page.on("pageerror",e=>problems.push(`[${vp.name}/${role}] JSエラー: ${e.message}`));
      page.on("dialog",d=>d.dismiss());
      await page.route(/fonts\.(googleapis|gstatic)\.com/,r=>r.abort());
      const shot=async(label)=>{
        await page.waitForTimeout(250);
        const over=await page.evaluate(()=>document.documentElement.scrollWidth-window.innerWidth);
        if(over>1)problems.push(`[${vp.name}/${role}] ${label}: 横に ${over}px はみ出しています`);
        await page.screenshot({path:path.join(OUT,`${vp.name}-${role}-${label}.png`),fullPage:true});
      };
      await page.goto(URL_);
      await page.evaluate(r=>{localStorage.clear();localStorage.setItem("stub_role",r);if(r==="teacher"){localStorage.setItem("stub_member","1")}},role);
      await page.reload();
      if(role==="student"){
        await shot("01-login");
        await page.evaluate(()=>localStorage.setItem("stub_logged","1"));await page.reload();await page.waitForTimeout(300);
        await shot("02-register");
        await page.fill("#nick","テスト受講者（長めのニックネーム）");await page.click("#psub");await page.waitForTimeout(300);
        await shot("03-home");
        await page.click('[data-subj="財務分析"]');await page.click('[data-count="10"]');await page.waitForTimeout(150);await shot("04-home-pick");
        await page.fill("#cnum","15");await page.press("#cnum","Enter");await page.locator("#cnum").blur();await page.waitForTimeout(150);
        const label=await page.textContent("#start");if(!label.includes("15問"))problems.push(`[${vp.name}] 好きな数を入力しても問題数が変わりません: ${label}`);
        await shot("04b-home-custom");
        await page.click("#start");await page.waitForTimeout(300);
        const total=await page.textContent(".qno");if(!/\/ 15/.test(total))problems.push(`[${vp.name}] 出題数が15問になっていません: ${total}`);
        await page.click("#stop");await page.click("#stopYes").catch(()=>{});await page.waitForTimeout(300);
        await page.click("#home").catch(()=>{});await page.waitForTimeout(200);
        await page.click('[data-count="all"]');await page.waitForTimeout(100);
        await page.click("#start");await page.waitForTimeout(400);await shot("05-question");
        for(let i=0;i<6;i++){await page.click(["#ans-true","#ans-false","#ans-unsure"][i%3]);await page.waitForTimeout(120)}
        await page.click("#stop");await page.waitForTimeout(150);await shot("06-stop-confirm");
        await page.click("#stopYes");await page.waitForTimeout(500);await shot("07-result");
        await page.click('[data-f="wrong"]');await page.waitForTimeout(150);await shot("08-result-wrong");
        await page.click('[data-view="history"]').catch(()=>{});await page.click("#home").catch(()=>{});await page.waitForTimeout(200);
        await page.click('[data-view="history"]');await page.waitForTimeout(300);await shot("09-history");
        await page.click("[data-exam]");await page.waitForTimeout(400);await shot("10-review");
        await page.click("#back");await page.waitForTimeout(200);
        await page.click(".who .linkbtn");await page.waitForTimeout(200);await shot("11-profile-edit");
      }else{
        await page.evaluate(()=>localStorage.setItem("stub_logged","1"));await page.reload();await page.waitForTimeout(300);
        await page.click('[data-view="teacher"]');await page.waitForTimeout(400);await shot("21-teacher");
        await page.click("#smp");await page.waitForTimeout(300);await shot("22-teacher-sample");
        await page.click(".li.click[data-uid]");await page.waitForTimeout(300);await shot("23-student-detail");
      }
      await ctx.close();
    }
  }
  await browser.close();server.close();
  console.log(problems.length?"問題あり:\n"+problems.join("\n"):"OK: 横はみ出し・JSエラーなし");
  console.log("スクリーンショット: "+OUT);
  process.exit(problems.length?1:0);
})();
