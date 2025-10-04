import router from '@ohos.router'
import common from '@ohos.app.ability.common'
import webview from '@ohos.web.webview'
import fs from '@ohos.file.fs'
import { DisplayManager } from '../utils/DisplayManager'

// 简易的 noVNC 加载器：从 rawfile/novnc/ 读取 novnc.min.js 并嵌入到 WebView
// 若未放置该文件，则显示提示文案。

interface VMInfoParam { name?: string; vncPort?: number }
interface VncRouteParams { vmInfo?: VMInfoParam }

@Entry
@Component
struct VNCViewer {
  @State vmName: string = ''
  @State vncPort: number = 5701
  @State statusText: string = '正在加载VNC页面…'
  @State displayConfig: any = null
  private webCtrl: webview.WebviewController = new webview.WebviewController()
  private displayManager: DisplayManager = DisplayManager.getInstance()

  aboutToAppear() {
    const params = router.getParams()
    if (params && typeof params === 'object') {
      const p = params as VncRouteParams
      if (p.vmInfo) {
        if (typeof p.vmInfo.name === 'string') this.vmName = p.vmInfo.name
        if (typeof p.vmInfo.vncPort === 'number') this.vncPort = p.vmInfo.vncPort
      }
    }
    
    // 初始化显示配置
    this.displayManager.updateVNCConfig({
      port: this.vncPort
    });
    this.displayManager.optimizeDisplaySettings();
    this.displayConfig = this.displayManager.getDisplayConfig();
    
    this.loadNoVnc()
  }

  private goBack() { router.back() }

  private async loadNoVnc() {
    try {
      this.statusText = '准备 noVNC 资源…'
      const ctx = getContext(this) as common.UIAbilityContext
      const rm = ctx.resourceManager
      // 尝试将 rawfile 的 noVNC 资源复制到 files 目录，并生成本地 html 再加载
      let hasNoVncMin: boolean = false
      let hasNoVncEsm: boolean = false
      let filesDir: string = '/data/storage/el2/base/haps/entry/files/novnc'
      try {
        await fs.mkdir(filesDir)
      } catch (_) {}
      try {
        const jsBytes: Uint8Array = await rm.getRawFileContent('novnc/novnc.min.js')
        const jsFile = await fs.open(filesDir + '/novnc.min.js', fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY)
        await fs.write(jsFile.fd, jsBytes.buffer.slice())
        await fs.close(jsFile)
        hasNoVncMin = true
      } catch (_) {
        hasNoVncMin = false
      }
      if (!hasNoVncMin) {
        try {
          const esmBytes: Uint8Array = await rm.getRawFileContent('novnc/novnc.esm.js')
          const esmFile = await fs.open(filesDir + '/novnc.esm.js', fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY)
          await fs.write(esmFile.fd, esmBytes.buffer.slice())
          await fs.close(esmFile)
          hasNoVncEsm = true
        } catch (_) {
          hasNoVncEsm = false
        }
      }
      this.statusText = hasNoVncMin ? '使用 UMD 版本加载 noVNC' : (hasNoVncEsm ? '使用 ESM 版本加载 noVNC' : '未找到 noVNC 资源')

      const htmlPath = filesDir + '/index.html'
      const baseUrl = 'file://' + filesDir + '/'
      const htmlHead = `<!DOCTYPE html><html><head><meta charset="utf-8" /><meta name="viewport" content="width=device-width, initial-scale=1" /><style>html,body,#root{height:100%;margin:0;padding:0;background:#000;color:#fff;font-family:system-ui,-apple-system}#toolbar{position:fixed;top:8px;left:8px;right:8px;display:flex;gap:8px;align-items:center}#screen{position:absolute;top:0;left:0;right:0;bottom:0;display:flex;align-items:center;justify-content:center}canvas{max-width:100%;max-height:100%;}</style></head><body>`
      const htmlBody = `<div id="toolbar"><span>noVNC</span><span id="status">Connecting ws://127.0.0.1:${this.vncPort}</span><button onclick="toggleFullscreen()">全屏</button></div><div id="screen"><canvas id="vncCanvas"></canvas></div>`
      const htmlScript = hasNoVncMin
        ? `<script>(function(){
              function tryLoad(srcs, onload, onerror){
                if(!srcs.length){ onerror && onerror(new Error('no source')); return; }
                var s=document.createElement('script');
                s.src=srcs[0]; s.onload=onload; s.onerror=function(){ tryLoad(srcs.slice(1), onload, onerror); };
                document.head.appendChild(s);
              }
              function toggleFullscreen(){
                if(!document.fullscreenElement){
                  document.documentElement.requestFullscreen();
                }else{
                  document.exitFullscreen();
                }
              }
              window.toggleFullscreen = toggleFullscreen;
              document.getElementById('status').innerText='加载 noVNC...';
              var candidates=['./novnc.min.js','internal://app/novnc/novnc.min.js','file://${filesDir}/novnc.min.js'];
              tryLoad(candidates, function(){
                try{ var RFB=window.RFB; if(!RFB){document.getElementById('status').innerText='noVNC脚本加载失败'; return;}
                  var target=document.getElementById('vncCanvas');
                  var rfb=new RFB(target,'ws://127.0.0.1:${this.vncPort}');
                  rfb.viewOnly=false; rfb.scaleViewport=true; rfb.background='#000';
                  rfb.addEventListener('connect',function(){document.getElementById('status').innerText='已连接 - 点击全屏按钮获得更好体验';});
                  rfb.addEventListener('disconnect',function(){document.getElementById('status').innerText='已断开';});
                  rfb.addEventListener('credentialsrequired',function(){document.getElementById('status').innerText='需要认证';});
                  rfb.addEventListener('securityfailure',function(e){document.getElementById('status').innerText='安全失败: '+e.detail.reason;});
                }catch(e){ document.getElementById('status').innerText='加载失败: '+e; }
              }, function(err){ document.getElementById('status').innerText='加载失败: '+err; });
            })();</script>`
        : (hasNoVncEsm
          ? `<script>(async function(){
                document.getElementById('status').innerText = '加载 noVNC ESM...';
                async function tryImports(specs){
                  let lastErr=null; for (const s of specs){ try { return await import(s);} catch(e){ lastErr=e; } }
                  throw lastErr||new Error('no spec');
                }
                try {
                  const mod = await tryImports(['./novnc.esm.js','internal://app/novnc/novnc.esm.js','file://${filesDir}/novnc.esm.js']);
                  window.RFB = (mod && (mod.default || mod.RFB)) || window.RFB;
                  if (!window.RFB) { document.getElementById('status').innerText='noVNC ESM 加载失败(无导出)'; return; }
                  var target=document.getElementById('vncCanvas');
                  var rfb=new window.RFB(target,'ws://127.0.0.1:${this.vncPort}');
                  rfb.viewOnly=false; rfb.scaleViewport=true; rfb.background='#000';
                  rfb.addEventListener('connect',function(){document.getElementById('status').innerText='已连接';});
                  rfb.addEventListener('disconnect',function(){document.getElementById('status').innerText='已断开';});
                } catch(e) {
                  document.getElementById('status').innerText = '加载失败: ' + e;
                }
              })();</script>`
          : `<script>document.body.innerHTML='<div style="color:#fff;padding:16px">缺少 noVNC 资源，请将 novnc.min.js 或 novnc.esm.js 放到 rawfile/novnc/ 目录</div>'</script>`)
      const htmlAll = htmlHead + htmlBody + htmlScript + '</body></html>'
      const htmlBytes = new Uint8Array(htmlAll.split('').map((c: string) => c.charCodeAt(0)))
      const htmlFile = await fs.open(htmlPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY)
      await fs.write(htmlFile.fd, htmlBytes)
      await fs.close(htmlFile)

      const fileUrl = 'file://' + htmlPath
      const internalUrl = 'internal://app/novnc/index.html'
      const dataUrl = 'data:text/html;charset=utf-8,' + encodeURIComponent(htmlAll)
      this.statusText = '正在打开 VNC 页面…'
      try {
        // 优先尝试 HarmonyOS 内部存储协议
        this.webCtrl.loadUrl(internalUrl)
        this.statusText = '已加载本地页面（internal://app）'
      } catch (e0) {
        try {
          // 再尝试用 file:// 直接加载
          this.webCtrl.loadUrl(fileUrl)
          this.statusText = '已加载本地页面（file://）'
        } catch (e1) {
          // 失败则回退到 data: URL
          this.statusText = 'file:// 加载失败，尝试 data: ' + (e1 as Error).message
          try {
            this.webCtrl.loadUrl(dataUrl)
            this.statusText = '已加载本地页面（data:）'
          } catch (e2) {
            this.statusText = '加载VNC页面失败: ' + (e2 as Error).message
          }
        }
      }
    } catch (e) {
      this.statusText = '加载VNC页面失败: ' + (e as Error).message
    }
  }

  build() {
    Column() {
      Row() {
        Button('返回').onClick(() => this.goBack())
        Text(this.vmName).fontSize(16).fontWeight(FontWeight.Medium).margin({ left: 8 })
      }.width('100%').padding(12)

      // 原生状态提示（即使 WebView 渲染失败，也可见）
      Text(this.statusText).fontSize(14).fontColor(Color.Grey).padding({ left: 12, right: 12, bottom: 8 })

      Web({ src: 'about:blank', controller: this.webCtrl })
        .javaScriptAccess(true)
        .fileAccess(true)
        .domStorageAccess(true)
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }
}
