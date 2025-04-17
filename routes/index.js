/**
 * index.js
 * Rotas principais da aplicação
 */
const express = require('express');
const router = express.Router();
const CameraManager = require('../models/CameraManager');
const LogManager = require('../models/LogManager');
const Auth = require('../models/Auth');
const HealthMonitor = require('../models/HealthMonitor');

// Middleware de autenticação para todas as rotas exceto login
router.use((req, res, next) => {
  if (req.path === '/login' || req.path === '/auth') {
    return next();
  }
  
  Auth.ensureAuthenticated(req, res, next);
});

// Página inicial - lista de câmeras
router.get('/', async (req, res) => {
    const cameras = CameraManager.listCameras();
    const cameraDetails = [];
    
    // Carregar links do YouTube
    let youtubeLinks = {};
    try {
      const fs = require('fs');
      const path = require('path');
      const configDir = path.dirname(require.resolve('../config/default'));
      const youtubeLinksPath = path.join(configDir, 'youtube_links.json');
      
      if (fs.existsSync(youtubeLinksPath)) {
        youtubeLinks = JSON.parse(fs.readFileSync(youtubeLinksPath, 'utf8'));
      }
    } catch (error) {
      console.error(`Erro ao carregar links do YouTube: ${error.message}`);
    }
  
    // Obter detalhes para cada câmera
    for (const camera of cameras) {
      const detalhes = CameraManager.getCameraDetails(camera);
      if (detalhes) {
        const pingResult = await CameraManager.pingCamera(detalhes.ip);
        
        cameraDetails.push({
          name: camera,
          ip: detalhes.ip,
          usuario: detalhes.usuario,
          senha: detalhes.senha,
          ping: pingResult,
          youtubeLink: youtubeLinks[camera] || '' // Adicionar link do YouTube
        });
      }
    }
  
    res.render('index', { 
      cameras: cameraDetails,
      youtubeLinks: youtubeLinks // Passar todos os links para a view
    });
  });

// Página de login
router.get('/login', (req, res) => {
  res.render('login');
});

// Processo de autenticação
router.post('/auth', (req, res) => {
  const { username, password } = req.body;
  
  if (Auth.validateCredentials(username, password)) {
    req.session.authenticated = true;
    req.session.username = username;
    return res.redirect('/');
  }
  
  return res.render('login', { error: 'Credenciais inválidas' });
});

// Adicione no seu arquivo routes/index.js

// Rota para o dashboard
router.get('/dashboard', async (req, res) => {
    res.render('dashboard');
  });
  
  // Rota para testar conexão com a câmera
  router.post('/api/camera/test-connection', async (req, res) => {
    const { ip, username, password, port, protocol } = req.body;
    
    try {
      // Testar ping
      const pingResult = await CameraManager.pingCamera(ip);
      
      // Se o ping falhar, retornar erro
      if (pingResult === 'Sem Comunicação') {
        return res.json({
          success: false,
          message: 'Não foi possível se conectar ao endereço IP',
          details: pingResult
        });
      }
      
      // Testar conexão RTSP
      const testCommand = `ffmpeg -rtsp_transport ${protocol} -i "rtsp://${username}:${password}@${ip}:${port}/cam/realmonitor?channel=1&subtype=0" -t 3 -c copy -y /tmp/test_camera.mp4`;
      
      const { stderr } = await exec(testCommand).catch(error => ({ stderr: error.message }));
      
      // Verificar se o teste foi bem-sucedido
      const success = !stderr.includes('Error') && !stderr.includes('error') && !stderr.includes('failed');
      
      return res.json({
        success,
        message: success ? 'Conexão bem-sucedida' : 'Falha na conexão RTSP',
        details: stderr
      });
    } catch (error) {
      return res.json({
        success: false,
        message: 'Erro ao testar conexão',
        details: error.message
      });
    }
  });
  
  // Rota para gerenciar cron
  router.post('/api/camera/:nomecamera/schedule', async (req, res) => {
    const { nomecamera } = req.params;
    const { interval, enabled } = req.body;
    
    try {
      if (enabled) {
        // Adicionar ou atualizar cron
        const result = CronManager.updateCronInterval(nomecamera, interval);
        if (result) {
          res.json({ success: true, message: 'Agendamento atualizado com sucesso' });
        } else {
          res.status(500).json({ success: false, message: 'Erro ao atualizar agendamento' });
        }
      } else {
        // Remover cron
        const result = CronManager.removeCronJob(nomecamera);
        if (result) {
          res.json({ success: true, message: 'Agendamento removido com sucesso' });
        } else {
          res.status(500).json({ success: false, message: 'Erro ao remover agendamento' });
        }
      }
    } catch (error) {
      res.status(500).json({ success: false, message: `Erro: ${error.message}` });
    }
  });
  
  // Rota para obter o status do agendamento
  router.get('/api/camera/:nomecamera/schedule', async (req, res) => {
    const { nomecamera } = req.params;
    
    try {
      const status = CronManager.getCronStatus(nomecamera);
      res.json(status);
    } catch (error) {
      res.status(500).json({ success: false, message: `Erro: ${error.message}` });
    }
  });
  
  // Rota para listar todos os agendamentos
  router.get('/api/schedules', async (req, res) => {
    try {
      const schedules = CronManager.listAllCronJobs();
      res.json({ schedules });
    } catch (error) {
      res.status(500).json({ success: false, message: `Erro: ${error.message}` });
    }
  });

// Logout
router.get('/logout', (req, res) => {
  req.session.destroy();
  res.redirect('/login');
});

// Adicionar câmera - formulário
router.get('/add_camera', (req, res) => {
  res.render('add_camera');
});

// Adicionar câmera - processamento
router.post('/add_camera', (req, res) => {
    const {
      nomecamera,
      ipcamera,
      usuariocamera,
      senhacamera,
      chaveyoutube,
      portartsp,
      protocolo,
      linkyoutube  // Novo campo
    } = req.body;
  
    CameraManager.createCameraScript(
        nomecamera,
        ipcamera,
        usuariocamera,
        senhacamera,
        chaveyoutube,
        portartsp || '554',
        protocolo || 'tcp'
      );
  
  // Salvar o link do YouTube em um arquivo JSON
  try {
    const fs = require('fs');
    const path = require('path');
    const configDir = path.dirname(require.resolve('../config/default'));
    const youtubeLinksPath = path.join(configDir, 'youtube_links.json');
    
    // Ler o arquivo existente ou criar um novo objeto
    let youtubeLinks = {};
    if (fs.existsSync(youtubeLinksPath)) {
      youtubeLinks = JSON.parse(fs.readFileSync(youtubeLinksPath, 'utf8'));
    }
    
    // Adicionar ou atualizar o link para esta câmera
    youtubeLinks[nomecamera] = linkyoutube || '';
    
    // Salvar o arquivo atualizado
    fs.writeFileSync(youtubeLinksPath, JSON.stringify(youtubeLinks, null, 2));
  } catch (error) {
    console.error(`Erro ao salvar link do YouTube: ${error.message}`);
  }

  res.redirect('/');
});

// Iniciar stream
router.post('/start_stream/:nomecamera', (req, res) => {
  const { nomecamera } = req.params;
  CameraManager.startStream(nomecamera);
  res.redirect('/');
});

// Parar stream
router.post('/stop_stream/:nomecamera', async (req, res) => {
  const { nomecamera } = req.params;
  await CameraManager.stopStream(nomecamera);
  res.redirect('/');
});

router.get('/edit_camera/:nomecamera', (req, res) => {
    const { nomecamera } = req.params;
    const detalhes = CameraManager.getCameraDetails(nomecamera);
    
    if (!detalhes) {
      return res.redirect('/');
    }
    
    // Carregar link do YouTube
    let youtubeLink = '';
    try {
      const fs = require('fs');
      const path = require('path');
      const configDir = path.dirname(require.resolve('../config/default'));
      const youtubeLinksPath = path.join(configDir, 'youtube_links.json');
      
      if (fs.existsSync(youtubeLinksPath)) {
        const youtubeLinks = JSON.parse(fs.readFileSync(youtubeLinksPath, 'utf8'));
        youtubeLink = youtubeLinks[nomecamera] || '';
      }
    } catch (error) {
      console.error(`Erro ao carregar link do YouTube: ${error.message}`);
    }
    
    res.render('edit_camera', { 
      camera_name: nomecamera, 
      detalhes,
      youtubeLink
    });
  });

// Editar câmera - processamento
router.post('/edit_camera/:nomecamera', (req, res) => {
    const { nomecamera } = req.params;
    const { 
      ipcamera, 
      usuariocamera, 
      senhacamera, 
      portartsp, 
      protocolo,
      linkyoutube  // Novo campo
    } = req.body;
    
    CameraManager.updateCameraDetails(nomecamera, {
      ipcamera,
      usuariocamera,
      senhacamera,
      portartsp,
      protocolo
    });
    
    // Atualizar link do YouTube
    try {
      const fs = require('fs');
      const path = require('path');
      const configDir = path.dirname(require.resolve('../config/default'));
      const youtubeLinksPath = path.join(configDir, 'youtube_links.json');
      
      // Ler o arquivo existente ou criar um novo objeto
      let youtubeLinks = {};
      if (fs.existsSync(youtubeLinksPath)) {
        youtubeLinks = JSON.parse(fs.readFileSync(youtubeLinksPath, 'utf8'));
      }
      
      // Atualizar o link para esta câmera
      youtubeLinks[nomecamera] = linkyoutube || '';
      
      // Salvar o arquivo atualizado
      fs.writeFileSync(youtubeLinksPath, JSON.stringify(youtubeLinks, null, 2));
    } catch (error) {
      console.error(`Erro ao atualizar link do YouTube: ${error.message}`);
    }
    
    res.redirect('/');
  });

// Visualizar logs
router.get('/view_logs/:nomecamera', (req, res) => {
  const { nomecamera } = req.params;
  res.render('view_logs', { nomecamera });
});

// Remover câmera
router.post('/remove_camera/:nomecamera', (req, res) => {
    const { nomecamera } = req.params;
    CameraManager.removeCamera(nomecamera);
    
    // Remover link do YouTube
    try {
      const fs = require('fs');
      const path = require('path');
      const configDir = path.dirname(require.resolve('../config/default'));
      const youtubeLinksPath = path.join(configDir, 'youtube_links.json');
      
      if (fs.existsSync(youtubeLinksPath)) {
        const youtubeLinks = JSON.parse(fs.readFileSync(youtubeLinksPath, 'utf8'));
        
        // Remover a entrada para esta câmera
        if (youtubeLinks[nomecamera]) {
          delete youtubeLinks[nomecamera];
          
          // Salvar o arquivo atualizado
          fs.writeFileSync(youtubeLinksPath, JSON.stringify(youtubeLinks, null, 2));
        }
      }
    } catch (error) {
      console.error(`Erro ao remover link do YouTube: ${error.message}`);
    }
    
    res.redirect('/');
  });
  

// Rota para obter logs (para AJAX)
router.get('/api/logs/:nomecamera', async (req, res) => {
  const { nomecamera } = req.params;
  const lines = req.query.lines || 20;
  const logs = await LogManager.tailLog(nomecamera, lines);
  res.json({ logs });
});

// Limpar logs
router.post('/clear_logs/:nomecamera', (req, res) => {
  const { nomecamera } = req.params;
  LogManager.clearLog(nomecamera);
  res.redirect(`/view_logs/${nomecamera}`);
});

// Rota para obter relatório de saúde completo
router.get('/api/health', async (req, res) => {
  try {
    const healthReport = await HealthMonitor.getFullHealthReport();
    res.json(healthReport);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Rota para obter apenas informações do sistema
router.get('/api/health/system', async (req, res) => {
  try {
    const systemHealth = await HealthMonitor.collectSystemHealth();
    res.json(systemHealth);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Rota para obter apenas informações das câmeras
router.get('/api/health/cameras', async (req, res) => {
  try {
    const camerasHealth = await HealthMonitor.collectCamerasHealth();
    res.json(camerasHealth);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Rota para verificar problemas críticos
router.get('/api/health/issues', async (req, res) => {
  try {
    await HealthMonitor.getFullHealthReport();
    const issues = HealthMonitor.checkForCriticalIssues();
    res.json({ issues });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Página de visualização de saúde do sistema
router.get('/system-health', async (req, res) => {
  res.render('system-health');

});


module.exports = router;