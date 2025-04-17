/**
 * app.js
 * Arquivo principal da aplicação
 */
const express = require('express');
const http = require('http');
const path = require('path');
const session = require('express-session');
const socketIo = require('socket.io');
const config = require('./config/default');
const LogManager = require('./models/LogManager');
const CameraManager = require('./models/CameraManager');
const activeTails = {};

// Inicializa a aplicação Express
const app = express();
const server = http.createServer(app);
const io = socketIo(server);

// Configurações
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.use(express.static(path.join(__dirname, 'public')));
app.use(express.urlencoded({ extended: true }));
app.use(express.json());

// Configuração de sessão
app.use(session({
  secret: config.server.secret,
  resave: false,
  saveUninitialized: true,
  cookie: { secure: false, maxAge: 3600000 } // 1 hora
}));

// Rotas
app.use('/', require('./routes/index'));



io.on('connection', (socket) => {
  console.log('Novo cliente conectado');
  
 // Inicia o monitoramento de logs
 socket.on('start_log', async (data) => {
    const { nomecamera } = data;
    console.log(`Iniciando monitoramento de log para ${nomecamera}`);
    
    // Obter status da câmera
    const status = await LogManager.getCameraStatus(nomecamera);
    socket.emit('log_update', {
      type: 'status',
      content: status
    });

    // Enviar as últimas linhas do log
    try {
        const lines = await LogManager.tailLog(nomecamera, 50);
        lines.forEach(line => {
          socket.emit('log_update', {
            type: 'log',
            content: line,
            timestamp: new Date().toISOString()
          });
        });
      } catch (error) {
        socket.emit('log_update', {
          type: 'error',
          content: `Erro ao recuperar logs: ${error.message}`,
          timestamp: new Date().toISOString()
        });
      }
      
      // Criar o seguidor de log
      const tail = LogManager.followLog(nomecamera, (logData) => {
        socket.emit('log_update', logData);
      });
      
      // Armazena o processo para encerrar quando o cliente desconectar
      if (tail) {
        const clientId = `${socket.id}-${nomecamera}`;
        activeTails[clientId] = tail;
        
      // Quando um cliente se desconecta
      socket.on('disconnect', () => {
        if (activeTails[clientId] && typeof activeTails[clientId].kill === 'function') {
          activeTails[clientId].kill();
          delete activeTails[clientId];
        } else {
          // Limpar o recurso de outra forma ou apenas remover da lista
          delete activeTails[clientId];
        }
      });
      }
    });
    
    // Reiniciar monitoramento de logs
    socket.on('restart_log', async (data) => {
      const { nomecamera } = data;
      console.log(`Reiniciando monitoramento de log para ${nomecamera}`);
      
      // Encerrar processo existente
      const clientId = `${socket.id}-${nomecamera}`;
      if (activeTails[clientId]) {
        activeTails[clientId].kill();
        delete activeTails[clientId];
      }
      
      // Iniciar novo monitoramento
      socket.emit('log_update', {
        type: 'system',
        content: 'Reiniciando monitoramento de logs...',
        timestamp: new Date().toISOString()
      });
      
      // Disparar evento start_log novamente
      socket.emit('start_log', { nomecamera });
    });
    
    // Monitor de status da câmera
    socket.on('monitor_cameras', async () => {
      const cameras = CameraManager.listCameras();
      const statusUpdates = [];
      
      for (const camera of cameras) {
        const details = CameraManager.getCameraDetails(camera);
        if (details) {
          const pingResult = await CameraManager.pingCamera(details.ip);
          const status = await LogManager.getCameraStatus(camera);
          
          statusUpdates.push({
            name: camera,
            ip: details.ip,
            ping: pingResult,
            status: status
          });
        }
      }
      
      socket.emit('camera_status_update', { cameras: statusUpdates });
    });
    
    // Solicitar status de uma câmera específica
    socket.on('get_camera_status', async (data) => {
      const { nomecamera } = data;
      const status = await LogManager.getCameraStatus(nomecamera);
      socket.emit('camera_status_update', { 
        camera: nomecamera,
        status: status
      });
    });
  });

  process.on('SIGINT', () => {
    LogManager.closeAll();
    process.exit(0);
  });
  
  process.on('SIGTERM', () => {
    LogManager.closeAll();
    process.exit(0);
  });

// Inicia o servidor
const PORT = config.server.port;
server.listen(PORT, () => {
  console.log(`Servidor rodando na porta ${PORT}`);
});

// Tratamento de exceções não capturadas
process.on('uncaughtException', (err) => {
  console.error('Exceção não capturada:', err);
});

module.exports = { app, server, io };