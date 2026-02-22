/**
 * 训练数据接收服务
 * 
 * 轻量级 HTTP 服务，用于接收 HarmonyOS 客户端上传的训练数据
 * 与 OpenClaw Gateway 运行在同一台机器上
 * 
 * 使用方式：
 *   node server/training-server.js
 * 
 * 端口：18790 (Gateway 是 18789)
 */

const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 18790;
const DATA_DIR = path.join(__dirname, 'training-data');

// 确保数据目录存在
if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

// 请求日志
function log(method, url, status, bodySize = 0) {
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}] ${method} ${url} ${status} ${bodySize}bytes`);
}

// CORS headers
const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Content-Type': 'application/json'
};

// 处理 OPTIONS 预检请求
function handleOptions(res) {
  res.writeHead(204, CORS_HEADERS);
  res.end();
}

// 处理健康检查
function handleHealth(res) {
  res.writeHead(200, CORS_HEADERS);
  res.end(JSON.stringify({ status: 'ok', timestamp: Date.now() }));
}

// 处理训练数据上传
function handleUpload(req, res) {
  let body = '';
  
  req.on('data', chunk => {
    body += chunk.toString();
    // 限制请求体大小 (1MB)
    if (body.length > 1024 * 1024) {
      res.writeHead(413, CORS_HEADERS);
      res.end(JSON.stringify({ error: 'Request body too large' }));
      req.destroy();
      return;
    }
  });
  
  req.on('end', () => {
    try {
      const payload = JSON.parse(body);
      
      // 验证基本结构
      if (!payload.deviceId || !payload.records || !Array.isArray(payload.records)) {
        res.writeHead(400, CORS_HEADERS);
        res.end(JSON.stringify({ error: 'Invalid payload structure' }));
        log('POST', '/training/upload', 400);
        return;
      }
      
      // 按设备ID保存数据
      const deviceId = payload.deviceId.replace(/[^a-zA-Z0-9_-]/g, '_');
      const date = new Date().toISOString().slice(0, 10);
      const filename = `${deviceId}_${date}.jsonl`;
      const filepath = path.join(DATA_DIR, filename);
      
      // 追加写入（每条记录一行 JSON）
      const lines = payload.records.map(r => JSON.stringify(r)).join('\n') + '\n';
      fs.appendFileSync(filepath, lines);
      
      const response = {
        success: true,
        receivedCount: payload.records.length,
        serverTime: Date.now(),
        file: filename
      };
      
      res.writeHead(200, CORS_HEADERS);
      res.end(JSON.stringify(response));
      log('POST', '/training/upload', 200, body.length);
      
      // 打印统计
      console.log(`  -> Saved ${payload.records.length} records from ${deviceId}`);
      
    } catch (err) {
      res.writeHead(400, CORS_HEADERS);
      res.end(JSON.stringify({ error: 'Invalid JSON: ' + err.message }));
      log('POST', '/training/upload', 400);
    }
  });
  
  req.on('error', err => {
    console.error('Request error:', err.message);
    res.writeHead(500, CORS_HEADERS);
    res.end(JSON.stringify({ error: 'Internal server error' }));
  });
}

// 处理数据统计
function handleStats(req, res) {
  try {
    const files = fs.readdirSync(DATA_DIR).filter(f => f.endsWith('.jsonl'));
    
    let totalRecords = 0;
    let totalBytes = 0;
    const deviceStats = {};
    
    for (const file of files) {
      const filepath = path.join(DATA_DIR, file);
      const stat = fs.statSync(filepath);
      const content = fs.readFileSync(filepath, 'utf8');
      const lines = content.trim().split('\n').filter(l => l.length > 0);
      
      totalRecords += lines.length;
      totalBytes += stat.size;
      
      // 从文件名提取设备ID
      const deviceId = file.split('_')[0];
      if (!deviceStats[deviceId]) {
        deviceStats[deviceId] = { files: 0, records: 0, bytes: 0 };
      }
      deviceStats[deviceId].files++;
      deviceStats[deviceId].records += lines.length;
      deviceStats[deviceId].bytes += stat.size;
    }
    
    const response = {
      totalFiles: files.length,
      totalRecords,
      totalBytes,
      totalMB: (totalBytes / 1024 / 1024).toFixed(2),
      devices: deviceStats
    };
    
    res.writeHead(200, CORS_HEADERS);
    res.end(JSON.stringify(response, null, 2));
    log('GET', '/training/stats', 200);
    
  } catch (err) {
    res.writeHead(500, CORS_HEADERS);
    res.end(JSON.stringify({ error: err.message }));
    log('GET', '/training/stats', 500);
  }
}

// 主请求处理器
const server = http.createServer((req, res) => {
  const url = req.url.split('?')[0];
  const method = req.method;
  
  // 路由
  if (method === 'OPTIONS') {
    handleOptions(res);
  } else if (url === '/health' && method === 'GET') {
    handleHealth(res);
  } else if (url === '/training/upload' && method === 'POST') {
    handleUpload(req, res);
  } else if (url === '/training/stats' && method === 'GET') {
    handleStats(req, res);
  } else {
    res.writeHead(404, CORS_HEADERS);
    res.end(JSON.stringify({ error: 'Not found' }));
    log(method, url, 404);
  }
});

server.listen(PORT, () => {
  console.log(`Training Data Server running on http://127.0.0.1:${PORT}`);
  console.log('');
  console.log('Endpoints:');
  console.log(`  GET  /health          - Health check`);
  console.log(`  POST /training/upload - Upload training data`);
  console.log(`  GET  /training/stats  - View statistics`);
  console.log('');
  console.log(`Data directory: ${DATA_DIR}`);
  console.log('');
});

// 优雅关闭
process.on('SIGINT', () => {
  console.log('\nShutting down...');
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});
