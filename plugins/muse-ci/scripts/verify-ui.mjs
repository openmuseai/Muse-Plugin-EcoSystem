import {chromium} from 'playwright-core';
import {mkdir,writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
const out=new URL('../docs/evidence/ui/',import.meta.url);await mkdir(out,{recursive:true});
const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
const result={viewports:[],interactions:[],errors:[]};
function check(ok,message){if(!ok)throw Error(message);}
async function nav(page,name){let el=page.locator(`[data-view="${name}"]:visible`).first();if(!await el.count()){await page.getByRole('button',{name:'更多',exact:true}).click();el=page.locator(`[data-view="${name}"]:visible`).first();}await el.click();}
try{
 for(const width of [1440,768,390]){
  const page=await browser.newPage({viewport:{width,height:1000},reducedMotion:'reduce'});page.on('pageerror',e=>result.errors.push(e.message));
  await page.goto('http://127.0.0.1:4178');
  for(const view of ['workflow','overview','plan','run','evidence','release','settings']){
   if(view!=='workflow')await nav(page,view);
   check(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),`Overflow ${width} ${view}`);
   check(await page.locator('h1').isVisible(),`Missing h1 ${view}`);
   await page.screenshot({path:fileURLToPath(new URL(`${width}-${view}.png`,out)),fullPage:true});
   result.viewports.push({width,view,overflow:false});
  }
  if(width===390){await nav(page,'overview');await page.getByRole('button',{name:'2 项决定待处理',exact:false}).click();check(await page.getByRole('dialog').isVisible(),'Mobile decision queue');await page.keyboard.press('Escape');result.interactions.push('mobile decision shortcut');}
  await page.close();
 }
 const page=await browser.newPage({viewport:{width:1440,height:1000}});page.on('pageerror',e=>result.errors.push(e.message));
 await page.goto('http://127.0.0.1:4178');await nav(page,'overview');await page.getByRole('button',{name:'新建交付',exact:true}).click();await page.locator('#new-goal').fill('验证移动端的数据授权与文档保存');await page.getByRole('button',{name:'创建计划',exact:false}).click();check(await page.locator('#plan-goal').inputValue()==='验证移动端的数据授权与文档保存','New plan lost');result.interactions.push('create plan');
 await page.getByRole('button',{name:'运行此计划',exact:true}).click();await page.getByRole('button',{name:'暂停',exact:true}).click();check(await page.getByRole('button',{name:'恢复演示',exact:true}).isVisible(),'Pause state');await page.getByRole('button',{name:'恢复演示',exact:true}).click();result.interactions.push('start pause resume');
 await page.getByRole('button',{name:'演示下一步',exact:false}).click();check(await page.getByRole('heading',{name:'下一步需要你的决定'}).isVisible(),'Decisions not blocking');
 for(let i=0;i<2;i++){await page.getByRole('button',{name:'查看并决定',exact:false}).first().click();await page.getByRole('button',{name:'记录本地决定',exact:true}).click();}
 await page.getByRole('button',{name:'恢复演示',exact:true}).click();for(let i=0;i<3;i++)await page.getByRole('button',{name:'演示下一步',exact:false}).click();check(await page.getByText('示例执行完成',{exact:true}).first().isVisible(),'Completion missing');result.interactions.push('decision gate and completion');
 await page.reload();check(await page.getByText('示例执行完成',{exact:true}).first().isVisible(),'Persisted run missing');result.interactions.push('local reload restore');
 await nav(page,'plan');await page.getByRole('button',{name:'运行此计划',exact:true}).click();await page.getByRole('button',{name:'取消运行',exact:true}).click();await page.keyboard.press('Escape');check(await page.getByRole('button',{name:'暂停',exact:true}).isVisible(),'Dismiss canceled run');await page.getByRole('button',{name:'取消运行',exact:true}).click();await page.getByRole('button',{name:'确认取消运行',exact:true}).click();check(await page.getByText('已取消',{exact:true}).first().isVisible(),'Cancel terminal state');result.interactions.push('cancel confirmation and dismissal');
 await nav(page,'evidence');await page.getByRole('button',{name:'设备',exact:true}).click();check(await page.locator('.evidence-row').count()===1,'Evidence filter');await page.getByRole('button',{name:'查看报告',exact:false}).click();check(await page.locator('dialog pre').innerText().then(t=>t.includes('preview-fixture')),'Fixture label missing');const downloadEvent=page.waitForEvent('download');await page.getByRole('button',{name:'下载示例报告',exact:false}).click();check((await downloadEvent).suggestedFilename()==='device-report.json','Report download name');await page.keyboard.press('Escape');result.interactions.push('evidence filter download and modal Escape');
 await nav(page,'release');check(await page.getByRole('button',{name:'尚不满足提审条件'}).isDisabled(),'Release gate not locked');result.interactions.push('submission remains blocked');
 await nav(page,'settings');await page.getByRole('button',{name:'管理示例连接',exact:false}).click();await page.getByRole('button',{name:'断开示例连接',exact:true}).click();await nav(page,'plan');check(await page.getByRole('button',{name:'运行此计划',exact:true}).isDisabled(),'Disconnected start allowed');result.interactions.push('disconnect gating');
 await page.close();
 const filePage=await browser.newPage();await filePage.goto(new URL('../web/index.html',import.meta.url).href);check(await filePage.getByRole('heading',{name:'Mobile 文档隔离与审核整改',exact:true}).isVisible(),'file preview failed');await filePage.goto(new URL('../dist/index.html',import.meta.url).href);check(await filePage.getByRole('heading',{name:'Mobile 文档隔离与审核整改',exact:true}).isVisible(),'built artifact failed');await filePage.close();result.interactions.push('direct file preview and standalone build');
 check(result.errors.length===0,'Browser errors: '+result.errors.join(';'));
 result.passed=true;await writeFile(new URL('verification.json',out),JSON.stringify(result,null,2));console.log(JSON.stringify(result,null,2));
}finally{await browser.close();}
