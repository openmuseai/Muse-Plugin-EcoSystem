import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import { McpServer } from '@modelcontextprotocol/server'
import { StdioServerTransport } from '@modelcontextprotocol/server/stdio'
import { z } from 'zod'
import { bundleRoot, setupJob, startSetup, status } from './setup.js'

const uri='ui://easel/setup'
const mimeType='text/html;profile=mcp-app'
const server=new McpServer({name:'io.openmuse/easel',version:'0.5.0'},{capabilities:{tools:{},resources:{}}})
function result(value:unknown){return {content:[{type:'text' as const,text:JSON.stringify(value)}],structuredContent:value as Record<string,unknown>}}

server.registerResource('Easel 安装与社媒工作台',uri,{title:'Easel 安装与社媒工作台',mimeType},async()=>({contents:[{uri,mimeType,text:await readFile(join(bundleRoot,'web','index.html'),'utf8')}]}))
server.registerTool('easel_open',{
  title:'打开 Easel',
  description:'打开 Easel 自有安装向导与社交媒体工作台。首次安装时请先完成依赖准备。',
  inputSchema:z.object({}),
  _meta:{ui:{resourceUri:uri,mimeType}},
},async()=>result({status:status()}))
server.registerTool('easel_setup_status',{
  title:'检查 Easel 依赖',
  description:'只读检查 Python、Playwright/Chromium、FFmpeg 和插件专用数据目录。',
  inputSchema:z.object({}),
},async()=>result(status()))
server.registerTool('easel_setup_start',{
  title:'安装 Easel 依赖',
  description:'用户确认后在其电脑上创建插件专用 Python 环境、安装 Pillow/Playwright/Chromium；可选择通过 Homebrew 安装 FFmpeg。安装异步进行。',
  inputSchema:z.object({
    python:z.string().optional().describe('Python 3.11–3.14 可执行文件绝对路径；留空时自动查找'),
    ffmpegDirectory:z.string().optional().describe('已有 ffmpeg 与 ffprobe 的目录'),
    installFfmpeg:z.boolean().describe('仅 macOS：同意执行 brew install ffmpeg'),
  }),
},async args=>result(startSetup(args)))
server.registerTool('easel_setup_job',{
  title:'查看 Easel 安装进度',
  description:'读取安装日志、结果和依赖状态。',
  inputSchema:z.object({jobId:z.string()}),
},async({jobId})=>result(setupJob(jobId)))

await server.connect(new StdioServerTransport())
