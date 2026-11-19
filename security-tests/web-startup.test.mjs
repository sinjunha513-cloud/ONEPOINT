import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const source=readFileSync(new URL('../web/flutter_bootstrap.js',import.meta.url),'utf8')
  .replace('{{flutter_js}}','').replace('{{flutter_build_config}}','');
async function boot({cache,workers,href='https://example.test/',ua='Chrome',webGL=true,engineError=false}={}) {
 const state={loaded:0,started:0,failed:0,reloads:[],config:null};
 const window={location:{href,replace:url=>state.reloads.push(url)},onepointStartup:{fail:()=>state.failed++}};
 Object.defineProperty(window,'caches',{get(){if(cache instanceof Error)throw cache;return cache}});
 Object.defineProperty(window,'sessionStorage',{get(){throw new Error('Session storage unavailable')}});
 const navigator={userAgent:ua};
 Object.defineProperty(navigator,'serviceWorker',{get(){if(workers instanceof Error)throw workers;return workers}});
 const context={window,navigator,URL,document:{baseURI:href,createElement:()=>({getContext:()=>webGL?{getExtension:()=>null}:null})},
   setTimeout:(fn,ms)=>setTimeout(fn,Math.min(ms,10)),clearTimeout,console:{error(){},warn(){}},
   _flutter:{loader:{load:async options=>{state.loaded++;state.config=options.config;
     await options.onEntrypointLoaded({initializeEngine:async config=>{
       assert.equal(config,options.config);if(engineError)throw Error('Renderer unavailable');
       return {runApp:async()=>state.started++};
     }});
   }}}};
 await vm.runInNewContext(source,context);
 return state;
}
test('denied cache, worker and session storage do not prevent startup',async()=>{
 const s=await boot({cache:Error('Denied'),workers:Error('Denied')});
 assert.equal(s.started,1);assert.equal(s.failed,0);assert.equal(s.reloads.length,0);
});
test('a hanging cache API cannot hold startup indefinitely',async()=>{
 const s=await boot({cache:{keys:()=>new Promise(()=>{})}});
 assert.equal(s.started,1);
});
test('legacy Flutter worker reloads once without depending on session storage',async()=>{
 const workers={controller:{scriptURL:'https://example.test/flutter_service_worker.js'},getRegistrations:async()=>[]};
 const first=await boot({workers});assert.equal(first.loaded,0);assert.equal(first.reloads.length,1);
 const second=await boot({workers,href:first.reloads[0]});assert.equal(second.started,1);assert.equal(second.reloads.length,0);
});
test('in-app and GPU-disabled browsers use CPU rendering with local engine files',async()=>{
 for(const options of [{ua:'Android KAKAOTALK/26'},{webGL:false}]){
   const s=await boot(options);assert.equal(s.started,1);assert.equal(s.config.canvasKitForceCpuOnly,true);
   assert.equal(s.config.canvasKitBaseUrl,'https://example.test/canvaskit/');
 }
});
test('engine failure reaches the retry UI instead of an unhandled rejection',async()=>{
 const s=await boot({engineError:true});assert.equal(s.started,0);assert.equal(s.failed,1);
});
