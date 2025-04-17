#!/bin/bash
# Script de instalação para o Sistema de Gerenciamento de Câmeras RTSP

# Cores para saída
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Função para exibir mensagens
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then
    print_error "Este script precisa ser executado como root (sudo)."
    exit 1
fi

# Verificar se o sistema é baseado em Ubuntu/Debian
if [ ! -f /etc/debian_version ]; then
    print_warning "Este script foi projetado para sistemas Ubuntu/Debian."
    read -p "Deseja continuar mesmo assim? (s/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        exit 1
    fi
fi

print_message "Iniciando instalação do Sistema de Gerenciamento de Câmeras RTSP..."

# Diretório de instalação
INSTALL_DIR="/opt/camera-manager"
CONFIG_DIR="/etc/camerastwspeed"

# Criar diretórios
print_message "Criando diretórios..."
mkdir -p $INSTALL_DIR
mkdir -p $CONFIG_DIR
chmod 755 $CONFIG_DIR

# Atualizar repositórios do sistema
print_message "Atualizando repositórios do sistema..."
apt update

# Instalar dependências
print_message "Instalando dependências..."
apt install -y curl build-essential ffmpeg git

# Verificar se o Node.js está instalado
if ! command -v node &> /dev/null; then
    print_message "Instalando Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt install -y nodejs
else
    print_message "Node.js já está instalado."
fi

# Verificar versão do Node.js
NODE_VERSION=$(node -v)
print_message "Versão do Node.js: $NODE_VERSION"

# Clonar ou atualizar repositório
if [ -d "$INSTALL_DIR/.git" ]; then
    print_message "Atualizando repositório existente..."
    cd $INSTALL_DIR
    git pull
else
    print_message "Clonando repositório..."
    # Se você tiver um repositório, substitua a URL abaixo
    # git clone https://github.com/seu-usuario/camera-manager.git $INSTALL_DIR
    
    # Caso contrário, criamos os arquivos manualmente
    print_message "Criando estrutura de arquivos..."
    mkdir -p $INSTALL_DIR/{config,models,public/{css,js},routes,views}
fi

# Criar arquivo de vídeo de manutenção se não existir
if [ ! -f "$CONFIG_DIR/twspeed.mp4" ]; then
    print_message "Criando arquivo de vídeo de manutenção..."
    # Usar ffmpeg para criar um vídeo de teste
    ffmpeg -f lavfi -i testsrc=duration=30:size=1280x720:rate=30 -f lavfi -i sine=frequency=1000:duration=30 \
    -c:v libx264 -c:a aac $CONFIG_DIR/twspeed.mp4
    print_message "Vídeo de manutenção criado em $CONFIG_DIR/twspeed.mp4"
else
    print_message "Arquivo de vídeo de manutenção já existe."
fi

# Criar imagem para marca d'água se não existir
if [ ! -f "$CONFIG_DIR/logo1.png" ]; then
    print_message "Criando imagem para marca d'água..."
    
    # Criar uma imagem PNG simples usando ImageMagick se estiver instalado
    if command -v convert &> /dev/null; then
        convert -size 200x100 xc:transparent -font Arial -pointsize 24 -fill white -stroke black \
        -gravity center -annotate 0 "TwSpeed Telecom" $CONFIG_DIR/logo1.png
        print_message "Imagem de marca d'água criada em $CONFIG_DIR/logo1.png"
    else
        print_warning "ImageMagick não encontrado. A imagem de marca d'água não foi criada."
        print_warning "Você pode adicionar sua própria imagem em $CONFIG_DIR/logo1.png"
        touch $CONFIG_DIR/logo1.png
    fi
else
    print_message "Imagem para marca d'água já existe."
fi

# Navegar para o diretório de instalação
cd $INSTALL_DIR

# Instalar dependências do Node.js
print_message "Instalando dependências do Node.js..."
npm init -y
npm install express ejs socket.io express-session ping nodemon

# Criar arquivo package.json
cat > $INSTALL_DIR/package.json << EOF
{
  "name": "camera-manager",
  "version": "1.0.0",
  "description": "Sistema de gerenciamento de câmeras RTSP para transmissão no YouTube",
  "main": "app.js",
  "scripts": {
    "start": "node app.js",
    "dev": "nodemon app.js",
    "test": "echo \\"Error: no test specified\\" && exit 1"
  },
  "author": "",
  "license": "ISC",
  "dependencies": {
    "ejs": "^3.1.9",
    "express": "^4.18.2",
    "express-session": "^1.17.3",
    "ping": "^0.4.4",
    "socket.io": "^4.7.2"
  },
  "devDependencies": {
    "nodemon": "^3.0.1"
  }
}
EOF

# Criar arquivo de configuração de systemd
print_message "Configurando serviço systemd..."
cat > /etc/systemd/system/camera-manager.service << EOF
[Unit]
Description=Camera Manager RTSP System
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/node app.js
Restart=on-failure
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=camera-manager

[Install]
WantedBy=multi-user.target
EOF

# Recarregar systemd
systemctl daemon-reload

# Copiar arquivos principais (ou criar se não existirem)
print_message "Criando arquivos principais..."

# Arquivo de configuração
cat > $INSTALL_DIR/config/default.js << EOF
/**
 * Configurações globais da aplicação
 */
module.exports = {
  // Diretório base para arquivos de câmeras
  basePath: '$CONFIG_DIR/',
  
  // Configurações do servidor
  server: {
    port: process.env.PORT || 3000,
    secret: process.env.SECRET_KEY || 'camera-manager-secret-key'
  },
  
  // Configurações de autenticação
  auth: {
    users: {
      admin: {
        password: process.env.ADMIN_PASSWORD || 'adminpass'
      }
    }
  },
  
  // Configurações padrão para câmeras
  camera: {
    defaultProtocol: 'tcp',
    defaultPort: '554',
    ffmpegPath: '/usr/bin/ffmpeg',
    logoPath: '$CONFIG_DIR/logo1.png',
    maintenanceVideo: '$CONFIG_DIR/twspeed.mp4'
  }
};
EOF

# Arquivo app.js principal
cat > $INSTALL_DIR/app.js << EOF
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

// Gerenciamento de WebSockets
const activeTails = {};

io.on('connection', (socket) => {
  console.log('Novo cliente conectado');
  
  // Inicia o monitoramento de logs
  socket.on('start_log', async (data) => {
    const { nomecamera } = data;
    console.log(\`Iniciando monitoramento de log para \${nomecamera}\`);
    
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
        content: \`Erro ao recuperar logs: \${error.message}\`,
        timestamp: new Date().toISOString()
      });
    }
    
    // Criar o seguidor de log
    const tail = LogManager.followLog(nomecamera, (logData) => {
      socket.emit('log_update', logData);
    });
    
    // Armazena o processo para encerrar quando o cliente desconectar
    if (tail) {
      const clientId = \`\${socket.id}-\${nomecamera}\`;
      activeTails[clientId] = tail;
      
      // Remove o processo quando o cliente desconectar
      socket.on('disconnect', () => {
        console.log(\`Cliente desconectado: \${clientId}\`);
        if (activeTails[clientId]) {
          activeTails[clientId].kill();
          delete activeTails[clientId];
        }
      });
    }
  });
  
  // Reiniciar monitoramento de logs
  socket.on('restart_log', async (data) => {
    const { nomecamera } = data;
    console.log(\`Reiniciando monitoramento de log para \${nomecamera}\`);
    
    // Encerrar processo existente
    const clientId = \`\${socket.id}-\${nomecamera}\`;
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
});

// Inicia o servidor
const PORT = config.server.port;
server.listen(PORT, () => {
  console.log(\`Servidor rodando na porta \${PORT}\`);
});

// Tratamento de exceções não capturadas
process.on('uncaughtException', (err) => {
  console.error('Exceção não capturada:', err);
});

// No encerramento gracioso do servidor
process.on('SIGINT', () => {
  LogManager.closeAll();
  process.exit(0);
});

process.on('SIGTERM', () => {
  LogManager.closeAll();
  process.exit(0);
});
EOF

# Copiar arquivos dos modelos
print_message "Copiando arquivos dos modelos..."

# Arquivo do modelo CameraManager.js
cat > $INSTALL_DIR/models/CameraManager.js << EOF
/**
 * CameraManager.js
 * Gerencia operações relacionadas às câmeras
 */
const fs = require('fs');
const path = require('path');
const { execSync, spawn } = require('child_process');
const config = require('../config/default');
const util = require('util');
const exec = util.promisify(require('child_process').exec);
const ping = require('ping');

class CameraManager {
  constructor() {
    this.basePath = config.basePath;
    
    // Garante que o diretório base exista
    if (!fs.existsSync(this.basePath)) {
      fs.mkdirSync(this.basePath, { recursive: true });
    }
  }

  /**
   * Cria script de controle para uma nova câmera
   */
  createCameraScript(nomecamera, ipcamera, usuariocamera, senhacamera, chaveyoutube, portartsp, protocolo) {
    const script = \`#! /bin/bash
date=$(date "+DATE: %d/%m/%Y %T")
ipcamera='\${ipcamera}'
nomecamera='\${nomecamera}'
usuariocamera='\${usuariocamera}'
senhacamera='\${senhacamera}'
chaveyoutube='\${chaveyoutube}'
processocamera=$(ps -aux |grep -v grep | grep -o "\${ipcamera}" | wc -l | grep -v grep;)
processomanu=$(ps -ef | grep "\${chaveyoutube}" | grep 'twspeed' | grep -v grep | wc -l | grep -v grep;)
portartsp='\${portartsp}'
protocolo='\${protocolo}'
function SteamingCamera () {
    log_file="\${this.basePath}$nomecamera.log"
    if [ "$processocamera" -ge "1" ]; then
        echo "" >> "$log_file"
        ps -ef | grep $chaveyoutube | grep 'manutencao' | grep -v grep | awk '{print $2}' | xargs kill -9;
    else
        ps -ef | grep "$chaveyoutube" | grep 'manutencao' | grep -v grep | awk '{print $2}' | xargs kill -9;
        echo "" >> "$log_file"
        ffmpeg -f lavfi -i anullsrc -rtsp_transport $protocolo -i "rtsp://$usuariocamera:$senhacamera@$ipcamera:$portartsp/cam/realmonitor?channel=1&subtype=0" \\\\
-vf "movie=\${config.camera.logoPath} [watermark]; [in][watermark] overlay=10:10" \\\\
-tune zerolatency -preset medium -pix_fmt yuv420p \\\\
-c:v libx264 -x264opts keyint=48:min-keyint=48:no-scenecut -b:v 2000k \\\\
-c:a aac -strict experimental -f flv rtmps://a.rtmp.youtube.com/live2/$chaveyoutube >> "$log_file" 2>&1
    fi
}

function SteamingManutencao () {
    if [ "$processomanu" -ge "1" ]; then
        ps -ef | grep "$ipcamera" | grep -v grep | awk '{print $2}' | xargs kill -9;
        echo "$date - Camera da $nomecamera com IP $ipcamera | Usuario: $usuariocamera | Senha: $senhacamera |  esta inacessivel" >> \${this.basePath}$nomecamera.log
    else
        ps -ef | grep "$ipcamera" | grep -v grep | awk '{print $2}' | xargs kill -9;
        echo "$date - Camera da $nomecamera com IP $ipcamera| Usuario: $usuariocamera | Senha: $senhacamera |  esta inacessivel" >> \${this.basePath}$nomecamera.log
        ffmpeg -stream_loop -1 -re -i \${config.camera.maintenanceVideo} -c:v libx264 -preset ultrafast -bufsize 5 -r 30 -b:v 500k -maxrate 1000k -f flv rtmps://a.rtmp.youtube.com/live2/$chaveyoutube &> /dev/null &
    fi
}
ping=$(ping -c 2 "$ipcamera" | grep 'received' | awk -F',' '{print $2}' | awk '{print $1}');
if [ "$ping" -ge 1 ]; then
    SteamingCamera;
else
    SteamingManutencao;
fi\`;

    const scriptPath = path.join(this.basePath, \`\${nomecamera}.sh\`);
    fs.writeFileSync(scriptPath, script);
    fs.chmodSync(scriptPath, 0o755);
    
    // Adicionar ao crontab
    try {
      const cronCommand = \`*/20 * * * * \${scriptPath} 2>&1\`;
      const currentCrontab = execSync('crontab -l').toString() || '';
      
      // Verificar se o job já existe
      if (!currentCrontab.includes(scriptPath)) {
        execSync(\`(crontab -l 2>/dev/null; echo "\${cronCommand}") | crontab -\`);
      }
      
      return true;
    } catch (error) {
      console.error(\`Erro ao atualizar crontab: \${error.message}\`);
      return false;
    }
  }

  /**
   * Inicia o streaming para a câmera
   */
  startStream(nomecamera) {
    const scriptPath = path.join(this.basePath, \`\${nomecamera}.sh\`);
    if (fs.existsSync(scriptPath)) {
      try {
        execSync(\`bash \${scriptPath}\`);
        return true;
      } catch (error) {
        console.error(\`Erro ao iniciar stream: \${error.message}\`);
        return false;
      }
    }
    return false;
  }

  /**
   * Para o streaming da câmera
   */
  async stopStream(nomecamera) {
    try {
      const detalhes = this.getCameraDetails(nomecamera);
      if (!detalhes || !detalhes.ip) return false;
      
      // Encerra processos relacionados à câmera
      await exec(\`ps -ef | grep "\${detalhes.ip}" | grep -v grep | awk '{print $2}' | xargs kill -9 2>/dev/null || true\`);
      
      // Garante que ffmpeg seja encerrado
      await exec('pkill -f ffmpeg || true');
      
      return true;
    } catch (error) {
      console.error(\`Erro ao parar stream: \${error.message}\`);
      return false;
    }
  }

  /**
   * Verifica conectividade da câmera
   */
  async pingCamera(ip) {
    if (!ip) return 'IP não encontrado';
    
    try {
      const res = await ping.promise.probe(ip, {
        timeout: 2,
        extra: ['-c', '2'],
      });
      
      if (!res.alive) return 'Sem Comunicação';
      return \`\${parseFloat(res.time).toFixed(2)} ms\`;
    } catch (error) {
      return 'Erro ao realizar ping';
    }
  }

  /**
   * Lista todas as câmeras configuradas
   */
  listCameras() {
    try {
      return fs.readdirSync(this.basePath)
        .filter(file => file.endsWith('.sh'))
        .map(file => file.replace('.sh', ''));
    } catch (error) {
      console.error(\`Erro ao listar câmeras: \${error.message}\`);
      return [];
    }
  }

  /**
   * Obtém detalhes de uma câmera específica
   */
  getCameraDetails(nomecamera) {
    const scriptPath = path.join(this.basePath, \`\${nomecamera}.sh\`);
    
    if (!fs.existsSync(scriptPath)) {
      return null;
    }
    
    try {
      const content = fs.readFileSync(scriptPath, 'utf8');
      
      // Extrair informações usando expressões regulares
      const detalhes = {
        ip: this.extractValue(content, "ipcamera='(.*)'"),
        usuario: this.extractValue(content, "usuariocamera='(.*)'"),
        senha: this.extractValue(content, "senhacamera='(.*)'"),
        portartsp: this.extractValue(content, "portartsp='(.*)'"),
        protocolo: this.extractValue(content, "protocolo='(.*)'"),
        chaveyoutube: this.extractValue(content, "chaveyoutube='(.*)'")
      };
      
      return detalhes;
    } catch (error) {
      console.error(\`Erro ao obter detalhes da câmera: \${error.message}\`);
      return null;
    }
  }

  /**
   * Atualiza informações de uma câmera
   */
  updateCameraDetails(nomecamera, novosDetalhes) {
    const scriptPath = path.join(this.basePath, \`\${nomecamera}.sh\`);
    
    if (!fs.existsSync(scriptPath)) {
      return false;
    }
    
    try {
      let content = fs.readFileSync(scriptPath, 'utf8');
      
      // Atualiza cada campo
      for (const [key, value] of Object.entries(novosDetalhes)) {
        if (value !== undefined) {
          // Cria um padrão regex que corresponde à definição da variável
          const pattern = new RegExp(\`\${key}='[^']+'\`);
          content = content.replace(pattern, \`\${key}='\${value}'\`);
        }
      }
      
      fs.writeFileSync(scriptPath, content);
      return true;
    } catch (error) {
      console.error(\`Erro ao atualizar detalhes da câmera: \${error.message}\`);
      return false;
    }
  }

  /**
   * Extrai valor usando regex
   */
  extractValue(content, pattern) {
    const match = content.match(new RegExp(pattern));
    return match ? match[1] : '';
  }

  /**
   * Remove uma câmera
   */
  removeCamera(nomecamera) {
    try {
      // Para o stream antes de remover
      this.stopStream(nomecamera);
      
      // Remove o script
      const scriptPath = path.join(this.basePath, \`\${nomecamera}.sh\`);
      if (fs.existsSync(scriptPath)) {
        fs.unlinkSync(scriptPath);
      }
      
      // Remove do crontab
      const currentCrontab = execSync('crontab -l').toString();
      const newCrontab = currentCrontab
        .split('\\n')
        .filter(line => !line.includes(\`/etc/camerastwspeed/\${nomecamera}.sh\`))
        .join('\\n');
      
      execSync(\`echo "\${newCrontab}" | crontab -\`);
      
      return true;
    } catch (error) {
      console.error(\`Erro ao remover câmera: \${error.message}\`);
      return false;
    }
  }
}

module.exports = new CameraManager();
EOF

# Arquivo do modelo LogManager.js
cat > $INSTALL_DIR/models/LogManager.js << EOF
/**
 * LogManager.js
 * Gerencia operações relacionadas aos logs das câmeras
 */
const fs = require('fs');
const path = require('path');
const { spawn, exec } = require('child_process');
const config = require('../config/default');
const util = require('util');
const execPromise = util.promisify(exec);

class LogManager {
  constructor() {
    this.basePath = config.basePath;
    this.activeStreams = {};
  }

  /**
   * Obtém o caminho do arquivo de log de uma câmera
   */
  getLogFile(nomecamera) {
    const logPath = path.join(this.basePath, \`\${nomecamera}.log\`);
    if (!fs.existsSync(logPath)) {
      // Criar o arquivo de log se não existir
      try {
        fs.writeFileSync(logPath, '');
      } catch (error) {
        console.error(\`Erro ao criar arquivo de log: \${error.message}\`);
        return null;
      }
    }
    return logPath;
  }

  /**
   * Retorna as últimas N linhas do log
   */
  async tailLog(nomecamera, lines = 10) {
    const logPath = this.getLogFile(nomecamera);
    if (!logPath) {
      return ['Arquivo de log não encontrado'];
    }

    try {
      const { stdout } = await execPromise(\`tail -n \${lines} "\${logPath}"\`);
      return stdout.split('\\n').filter(Boolean);
    } catch (error) {
      console.error(\`Erro ao obter logs: \${error.message}\`);
      return ['Erro ao obter logs'];
    }
  }

  /**
   * Segue o arquivo de log em tempo real (para uso com WebSockets)
   */
  followLog(nomecamera, callback) {
    const logPath = this.getLogFile(nomecamera);
    if (!logPath) {
      callback({
        type: 'error',
        content: 'Arquivo de log não encontrado'
      });
      return null;
    }

    // Verificar se já existe um processo ativo para esta câmera
    if (this.activeStreams[nomecamera]) {
      this.activeStreams[nomecamera].kill();
      delete this.activeStreams[nomecamera];
    }

    // Obter o status atual da câmera
    this.getCameraStatus(nomecamera).then(status => {
      callback({
        type: 'status',
        content: status
      });
    });

    const tail = spawn('tail', ['-f', logPath]);
    this.activeStreams[nomecamera] = tail;
    
    tail.stdout.on('data', (data) => {
      data.toString().split('\\n').filter(Boolean).forEach(line => {
        callback({
          type: 'log',
          content: line,
          timestamp: new Date().toISOString()
        });
      });
    });
    
    tail.stderr.on('data', (data) => {
      console.error(\`Erro ao seguir log: \${data}\`);
      callback({
        type: 'error',
        content: \`Erro: \${data}\`
      });
    });
    
    tail.on('close', (code) => {
      callback({
        type: 'system',
        content: \`Monitoramento de logs encerrado (código: \${code})\`
      });
      delete this.activeStreams[nomecamera];
    });
    
    return tail;
  }

  /**
   * Obtém o status atual da câmera (em execução ou parada)
   */
  async getCameraStatus(nomecamera) {
    try {
      // Verificar se existe um processo ffmpeg para esta câmera
      const { stdout } = await execPromise(\`ps aux | grep ffmpeg | grep "\${nomecamera}" | grep -v grep | wc -l\`);
      const count = parseInt(stdout.trim(), 10);
      
      if (count > 0) {
        return {
          running: true,
          message: 'Transmissão ativa',
          since: await this.getStreamStartTime(nomecamera)
        };
      } else {
        return {
          running: false,
          message: 'Transmissão inativa',
          lastRun: await this.getLastRunTime(nomecamera)
        };
      }
    } catch (error) {
      console.error(\`Erro ao verificar status da câmera: \${error.message}\`);
      return {
        running: false,
        message: 'Erro ao verificar status',
        error: error.message
      };
    }
  }

  /**
   * Obtém o tempo de início da transmissão atual
   */
  async getStreamStartTime(nomecamera) {
    try {
      const { stdout } = await execPromise(\`ps -o lstart= -p $(ps aux | grep ffmpeg | grep "\${nomecamera}" | grep -v grep | awk '{print $2}' | head -1)\`);
      return stdout.trim();
    } catch (error) {
      return 'Desconhecido';
    }
  }

 /**
   * Obtém o horário da última execução baseado no arquivo de log
   */
  async getLastRunTime(nomecamera) {
    const logPath = this.getLogFile(nomecamera);
    if (!logPath) return 'Desconhecido';
    
    try {
      const { stdout } = await execPromise(`stat -c %y "${logPath}"`);
      return stdout.trim();
    } catch (error) {
      return 'Desconhecido';
    }
  }

  /**
   * Limpa o arquivo de log
   */
  clearLog(nomecamera) {
    const logPath = this.getLogFile(nomecamera);
    if (!logPath) return false;
    
    try {
      fs.writeFileSync(logPath, `=== Log limpo em ${new Date().toISOString()} ===\n`);
      return true;
    } catch (error) {
      console.error(`Erro ao limpar log: ${error.message}`);
      return false;
    }
  }

  /**
   * Encerra todos os processos de monitoramento ativos
   */
  closeAll() {
    Object.values(this.activeStreams).forEach(process => {
      if (process && typeof process.kill === 'function') {
        process.kill();
      }
    });
    this.activeStreams = {};
  }
}

module.exports = new LogManager();
EOF

  /**
   * Limpa o arquivo de log
   */#!/bin/bash
# Script de instalação para o Sistema de Gerenciamento de Câmeras RTSP

# Cores para saída
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Função para exibir mensagens
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then
    print_error "Este script precisa ser executado como root (sudo)."
    exit 1
fi

# Verificar se o sistema é baseado em Ubuntu/Debian
if [ ! -f /etc/debian_version ]; then
    print_warning "Este script foi projetado para sistemas Ubuntu/Debian."
    read -p "Deseja continuar mesmo assim? (s/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        exit 1
    fi
fi

print_message "Iniciando instalação do Sistema de Gerenciamento de Câmeras RTSP..."

# Diretório de instalação
INSTALL_DIR="/opt/camera-manager"
CONFIG_DIR="/etc/camerastwspeed"

# Criar diretórios
print_message "Criando diretórios..."
mkdir -p $INSTALL_DIR
mkdir -p $CONFIG_DIR
chmod 755 $CONFIG_DIR

# Atualizar repositórios do sistema
print_message "Atualizando repositórios do sistema..."
apt update

# Instalar dependências
print_message "Instalando dependências..."
apt install -y curl build-essential ffmpeg git

# Verificar se o Node.js está instalado
if ! command -v node &> /dev/null; then
    print_message "Instalando Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt install -y nodejs
else
    print_message "Node.js já está instalado."
fi

# Verificar versão do Node.js
NODE_VERSION=$(node -v)
print_message "Versão do Node.js: $NODE_VERSION"

# Clonar ou atualizar repositório
if [ -d "$INSTALL_DIR/.git" ]; then
    print_message "Atualizando repositório existente..."
    cd $INSTALL_DIR
    git pull
else
    print_message "Clonando repositório..."
    # Se você tiver um repositório, substitua a URL abaixo
    # git clone https://github.com/seu-usuario/camera-manager.git $INSTALL_DIR
    
    # Caso contrário, criamos os arquivos manualmente
    print_message "Criando estrutura de arquivos..."
    mkdir -p $INSTALL_DIR/{config,models,public/{css,js},routes,views}
fi

# Criar arquivo de vídeo de manutenção se não existir
if [ ! -f "$CONFIG_DIR/twspeed.mp4" ]; then
    print_message "Criando arquivo de vídeo de manutenção..."
    # Usar ffmpeg para criar um vídeo de teste
    ffmpeg -f lavfi -i testsrc=duration=30:size=1280x720:rate=30 -f lavfi -i sine=frequency=1000:duration=30 \
    -c:v libx264 -c:a aac $CONFIG_DIR/twspeed.mp4
    print_message "Vídeo de manutenção criado em $CONFIG_DIR/twspeed.mp4"
else
    print_message "Arquivo de vídeo de manutenção já existe."
fi

# Criar imagem para marca d'água se não existir
if [ ! -f "$CONFIG_DIR/logo1.png" ]; then
    print_message "Criando imagem para marca d'água..."
    
    # Criar uma imagem PNG simples usando ImageMagick se estiver instalado
    if command -v convert &> /dev/null; then
        convert -size 200x100 xc:transparent -font Arial -pointsize 24 -fill white -stroke black \
        -gravity center -annotate 0 "TwSpeed Telecom" $CONFIG_DIR/logo1.png
        print_message "Imagem de marca d'água criada em $CONFIG_DIR/logo1.png"
    else
        print_warning "ImageMagick não encontrado. A imagem de marca d'água não foi criada."
        print_warning "Você pode adicionar sua própria imagem em $CONFIG_DIR/logo1.png"
        touch $CONFIG_DIR/logo1.png
    fi
else
    print_message "Imagem para marca d'água já existe."
fi

# Navegar para o diretório de instalação
cd $INSTALL_DIR

# Instalar dependências do Node.js
print_message "Instalando dependências do Node.js..."
npm init -y
npm install express ejs socket.io express-session ping nodemon

# Criar arquivo package.json
cat > $INSTALL_DIR/package.json << EOF
{
  "name": "camera-manager",
  "version": "1.0.0",
  "description": "Sistema de gerenciamento de câmeras RTSP para transmissão no YouTube",
  "main": "app.js",
  "scripts": {
    "start": "node app.js",
    "dev": "nodemon app.js",
    "test": "echo \\"Error: no test specified\\" && exit 1"
  },
  "author": "",
  "license": "ISC",
  "dependencies": {
    "ejs": "^3.1.9",
    "express": "^4.18.2",
    "express-session": "^1.17.3",
    "ping": "^0.4.4",
    "socket.io": "^4.7.2"
  },
  "devDependencies": {
    "nodemon": "^3.0.1"
  }
}
EOF

# Criar arquivo de configuração de systemd
print_message "Configurando serviço systemd..."
cat > /etc/systemd/system/camera-manager.service << EOF
[Unit]
Description=Camera Manager RTSP System
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/node app.js
Restart=on-failure

clearLog(nomecamera) {
    const logPath = this.getLogFile(nomecamera);
    if (!logPath) return false;
    
    try {
      fs.writeFileSync(logPath, `=== Log limpo em ${new Date().toISOString()} ===\n`);
      return true;
    } catch (error) {
      console.error(`Erro ao limpar log: ${error.message}`);
      return false;
    }
  }

  /**
   * Encerra todos os processos de monitoramento ativos
   */
  closeAll() {
    Object.values(this.activeStreams).forEach(process => {
      if (process && typeof process.kill === 'function') {
        process.kill();
      }
    });
    this.activeStreams = {};
  }
}

module.exports = new LogManager();
EOF

# Arquivo de rotas
cat > $INSTALL_DIR/routes/index.js << EOF
/**
 * index.js
 * Rotas principais da aplicação
 */
const express = require('express');
const router = express.Router();
const CameraManager = require('../models/CameraManager');
const LogManager = require('../models/LogManager');
const Auth = require('../models/Auth');

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
        ping: pingResult
      });
    }
  }
  
  res.render('index', { cameras: cameraDetails });
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
    protocolo 
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

// Editar câmera - formulário
router.get('/edit_camera/:nomecamera', (req, res) => {
  const { nomecamera } = req.params;
  const detalhes = CameraManager.getCameraDetails(nomecamera);
  
  if (!detalhes) {
    return res.redirect('/');
  }
  
  res.render('edit_camera', { camera_name: nomecamera, detalhes });
});

// Editar câmera - processamento
router.post('/edit_camera/:nomecamera', (req, res) => {
  const { nomecamera } = req.params;
  const { ipcamera, usuariocamera, senhacamera, portartsp, protocolo } = req.body;
  
  CameraManager.updateCameraDetails(nomecamera, {
    ipcamera,
    usuariocamera,
    senhacamera,
    portartsp,
    protocolo
  });
  
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
  res.redirect(\`/view_logs/\${nomecamera}\`);
});

module.exports = router;
EOF

# Criar modelo de autenticação
cat > $INSTALL_DIR/models/Auth.js << EOF
/**
 * Auth.js
 * Gerencia autenticação de usuários
 */
const config = require('../config/default');

class Auth {
  constructor() {
    this.users = config.auth.users;
  }

  /**
   * Verifica se as credenciais são válidas
   */
  validateCredentials(username, password) {
    if (!this.users[username]) {
      return false;
    }
    
    return this.users[username].password === password;
  }

  /**
   * Middleware para proteger rotas
   */
  ensureAuthenticated(req, res, next) {
    if (req.session && req.session.authenticated) {
      return next();
    }
    
    // Redireciona para login
    return res.redirect('/login');
  }
}

module.exports = new Auth();
EOF

# Criar arquivo de estilo CSS
mkdir -p $INSTALL_DIR/public/css
cat > $INSTALL_DIR/public/css/style.css << EOF
/* Estilos globais */
:root {
  --primary-color: #007bff;
  --primary-hover: #0056b3;
  --danger-color: #e60000;
  --danger-hover: #3d0000;
  --success-color: #00804a;
  --success-hover: #00663b;
  --bg-color: #f0f0f0;
  --card-bg: #ffffff;
  --border-radius: 10px;
  --box-shadow: 0 4px 8px rgba(0, 0, 0, 0.1);
}

body {
  font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
  background-color: var(--bg-color);
  margin: 0;
  padding: 0;
  min-height: 100vh;
  display: flex;
  flex-direction: column;
}

.container {
  width: 90%;
  max-width: 1200px;
  margin: 20px auto;
  padding: 20px;
}

/* Cabeçalho */
.header {
  background-color: var(--primary-color);
  color: white;
  padding: 1rem;
  text-align: center;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
}

.header h1 {
  margin: 0;
}

.nav {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0 1rem;
  background-color: #fff;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.12);
}

.nav-links {
  display: flex;
}

.nav-links a {
  color: var(--primary-color);
  text-decoration: none;
  padding: 1rem;
  transition: background-color 0.3s ease;
}

.nav-links a:hover {
  background-color: rgba(0, 123, 255, 0.1);
}

.user-info {
  display: flex;
  align-items: center;
}

.user-info span {
  margin-right: 1rem;
}

/* Cards de câmeras */
.section-title {
  margin: 2rem 0 1rem;
  color: #333;
  font-size: 1.5rem;
  border-bottom: 2px solid #eee;
  padding-bottom: 0.5rem;
}

.camera-cards {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-start;
  gap: 20px;
  margin: 0;
  padding: 0;
  list-style-type: none;
}

.camera-card {
  background-color: var(--card-bg);
  border-radius: var(--border-radius);
  box-shadow: var(--box-shadow);
  padding: 15px;
  flex: 0 0 calc(33.333% - 20px);
  box-sizing: border-box;
  transition: transform 0.3s ease, box-shadow 0.3s ease;
}

.camera-card:hover {
  transform: translateY(-5px);
  box-shadow: 0 6px 12px rgba(0, 0, 0, 0.15);
}

.camera-card h2 {
  margin-top: 0;
  margin-bottom: 15px;
  color: #333;
  font-size: 1.2rem;
  border-bottom: 1px solid #eee;
  padding-bottom: 8px;
}

.camera-card p {
  margin: 8px 0;
  font-size: 0.9rem;
  color: #555;
}

.camera-card .status {
  font-weight: bold;
}

.camera-card .status.online {
  color: var(--success-color);
}

.camera-card .status.offline {
  color: var(--danger-color);
}

.camera-actions {
  display: flex;
  justify-content: space-between;
  margin-top: 15px;
}

/* Botões */
.btn {
  display: inline-block;
  padding: 8px 12px;
  border: none;
  border-radius: 4px;
  font-size: 0.9rem;
  cursor: pointer;
  text-align: center;
  text-decoration: none;
  transition: background-color 0.3s;
}

.btn-primary {
  background-color: var(--primary-color);
  color: white;
}

.btn-primary:hover {
  background-color: var(--primary-hover);
}

.btn-danger {
  background-color: var(--danger-color);
  color: white;
}

.btn-danger:hover {
  background-color: var(--danger-hover);
}

.btn-success {
  background-color: var(--success-color);
  color: white;
}

.btn-success:hover {
  background-color: var(--success-hover);
}

/* Links */
.link {
  color: var(--primary-color);
  text-decoration: none;
  font-size: 0.9rem;
  transition: color 0.3s;
}

.link:hover {
  color: var(--primary-hover);
  text-decoration: underline;
}

/* Formulários */
.form-container {
  background-color: white;
  border-radius: var(--border-radius);
  box-shadow: var(--box-shadow);
  padding: 25px;
  max-width: 500px;
  margin: 40px auto;
}

.form-group {
  margin-bottom: 20px;
}

.form-group label {
  display: block;
  margin-bottom: 8px;
  font-weight: 500;
  color: #333;
}

.form-control {
  width: 100%;
  padding: 10px;
  border: 1px solid #ddd;
  border-radius: 4px;
  font-size: 16px;
  box-sizing: border-box;
  transition: border-color 0.3s;
}

.form-control:focus {
  border-color: var(--primary-color);
  outline: none;
}

.form-actions {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-top: 30px;
}

/* Visualizador de logs */
.log-container {
  background-color: #1e1e1e;
  color: #f8f8f8;
  border-radius: var(--border-radius);
  padding: 20px;
  height: 70vh;
  overflow-y: auto;
  font-family: 'Courier New', Courier, monospace;
  font-size: 0.9rem;
}

.log-line {
  margin: 5px 0;
  line-height: 1.4;
  white-space: pre-wrap;
  word-break: break-all;
}

.log-actions {
  display: flex;
  justify-content: space-between;
  margin: 20px 0;
}

/* Stream ao vivo */
.streams-section {
  margin-top: 30px;
}

.stream-container {
  display: flex;
  flex-wrap: wrap;
  gap: 20px;
  justify-content: center;
}

.stream-iframe {
  border: none;
  border-radius: 8px;
  box-shadow: var(--box-shadow);
}

/* Responsividade */
@media (max-width: 1024px) {
  .camera-card {
    flex: 0 0 calc(50% - 20px);
  }
}

@media (max-width: 768px) {
  .camera-card {
    flex: 0 0 100%;
  }
  
  .nav {
    flex-direction: column;
    padding: 0;
  }
  
  .nav-links {
    flex-direction: column;
    width: 100%;
  }
  
  .nav-links a {
    width: 100%;
    text-align: center;
    border-bottom: 1px solid #eee;
  }
  
  .stream-iframe {
    width: 90%;
    height: auto;
  }
}
EOF

# Criar templates EJS mínimos
mkdir -p $INSTALL_DIR/views

# Template de login
cat > $INSTALL_DIR/views/login.ejs << EOF
<!DOCTYPE html>
<html lang="pt-br">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Login - Gerenciador de Câmeras</title>
  <link rel="stylesheet" href="/css/style.css">
  <style>
    body {
      display: flex;
      justify-content: center;
      align-items: center;
      height: 100vh;
      background-color: #f5f5f5;
    }
    
    .login-container {
      background-color: white;
      border-radius: 10px;
      box-shadow: 0 4px 8px rgba(0, 0, 0, 0.1);
      padding: 30px;
      width: 360px;
      text-align: center;
    }
    
    .login-title {
      margin-bottom: 20px;
      color: #333;
    }
    
    .error-message {
      color: #e60000;
      margin-bottom: 20px;
      padding: 10px;
      background-color: rgba(230, 0, 0, 0.1);
      border-radius: 5px;
    }
  </style>
</head>
<body>
  <div class="login-container">
    <h1 class="login-title">Gerenciador de Câmeras</h1>
    <% if (locals.error) { %>
      <div class="error-message"><%= error %></div>
    <% } %>
    <form action="/auth" method="post">
      <div class="form-group">
        <label for="username">Usuário:</label>
        <input type="text" id="username" name="username" class="form-control" required>
      </div>
      <div class="form-group">
        <label for="password">Senha:</label>
        <input type="password" id="password" name="password" class="form-control" required>
      </div>
      <button type="submit" class="btn btn-primary" style="width: 100%;">Entrar</button>
    </form>
  </div>
</body>
</html>
EOF

# Template de página inicial
cat > $INSTALL_DIR/views/index.ejs << EOF
<!DOCTYPE html>
<html lang="pt-br">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Gerenciador de Câmeras RTSP</title>
  <link rel="stylesheet" href="/css/style.css">
  <script src="https://cdnjs.cloudflare.com/ajax/libs/socket.io/4.0.0/socket.io.min.js"></script>
</head>
<body>
  <!-- Cabeçalho -->
  <header class="header">
    <h1>Painel de Controle de Câmeras</h1>
  </header>
  
  <!-- Barra de navegação -->
  <nav class="nav">
    <div class="nav-links">
      <a href="/">Início</a>
      <a href="/add_camera">Adicionar Câmera</a>
    </div>
    <div class="user-info">
      <span>Bem-vindo, Admin</span>
      <a href="/logout" class="btn btn-danger">Sair</a>
    </div>
  </nav>
  
  <div class="container">
    <!-- Seção de câmeras ativas -->
    <h2 class="section-title">Câmeras Ativas</h2>
    
    <% if (cameras.length === 0) { %>
      <p>Nenhuma câmera cadastrada. <a href="/add_camera" class="link">Adicionar agora</a></p>
    <% } else { %>
      <div class="camera-cards">
        <% cameras.forEach(function(camera) { %>
          <div class="camera-card">
            <h2><%= camera.name %></h2>
            <p>IP: <span><%= camera.ip %></span></p>
            <p>Status: <span class="status <%= camera.ping === 'Sem Comunicação' ? 'offline' : 'online' %>">
              <%= camera.ping === 'Sem Comunicação' ? 'Offline' : 'Online' %> (<%= camera.ping %>)
            </span></p>
            
            <div class="camera-actions">
              <form action="/start_stream/<%= camera.name %>" method="post" style="display: inline;">
                <button type="submit" class="btn btn-success">Iniciar Stream</button>
              </form>
              
              <form action="/stop_stream/<%= camera.name %>" method="post" style="display: inline;">
                <button type="submit" class="btn btn-danger">Parar Stream</button>
              </form>
            </div>
            
            <div class="camera-links" style="margin-top: 15px;">
              <a href="/view_logs/<%= camera.name %>" class="link">Ver Logs</a>
              <a href="/edit_camera/<%= camera.name %>" class="link" style="margin-left: 10px;">Editar</a>
              
              <form action="/remove_camera/<%= camera.name %>" method="post" style="display: inline; float: right;">
                <button type="submit" class="btn btn-danger" onclick="return confirm('Tem certeza que deseja remover esta câmera?');">
                  Remover
                </button>
              </form>
            </div>
          </div>
        <% }); %>
      </div>
    <% } %>
    
    <!-- Seção de streams ao vivo -->
    <h2 class="section-title">Streams ao Vivo</h2>
    <div class="stream-container">
      <iframe width="400" height="225" src="https://www.youtube.com/embed/d_YGy_dRN4g?autoplay=1" 
              title="Jardim Umuarama - Acompanhe Sinop" class="stream-iframe"
              allow="accelerometer; autoplay=1; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" 
              referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>
              
      <iframe width="400" height="225" src="https://www.youtube.com/embed/xq-M928zp5M?autoplay=1" 
              title="Jardim das Acacias - Acompanhe Sinop" class="stream-iframe"
              allow="accelerometer; autoplay=1; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" 
              referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>
    </div>
  </div>
  
  <script>
    document.addEventListener('DOMContentLoaded', function() {
      const socket = io();
      
      // Atualizar status das câmeras a cada 30 segundos
      setInterval(() => {
        socket.emit('monitor_cameras');
      }, 30000);
      
      // Receber atualizações de status
      socket.on('camera_status_update', function(data) {
        const cameras = data.cameras;
        
        cameras.forEach(camera => {
          const cardElements = document.querySelectorAll('.camera-card h2');
          
          cardElements.forEach(nameElement => {
            if (nameElement.textContent === camera.name) {
              const cardElement = nameElement.closest('.camera-card');
              if (cardElement) {
                const statusElement = cardElement.querySelector('.status');
                
                if (camera.ping === 'Sem Comunicação') {
                  statusElement.textContent = \`Offline (\${camera.ping})\`;
                  statusElement.className = 'status offline';
                } else {
                  statusElement.textContent = \`Online (\${camera.ping})\`;
                  statusElement.className = 'status online';
                }
              }
            }
          });
        });
      });
    });
  </script>
</body>
</html>
EOF

# Template para adicionar câmera
cat > $INSTALL_DIR/views/add_camera.ejs << EOF
<!DOCTYPE html>
<html lang="pt-br">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Adicionar Câmera</title>
  <link rel="stylesheet" href="/css/style.css">
</head>
<body>
  <!-- Cabeçalho -->
  <header class="header">
    <h1>Adicionar Nova Câmera</h1>
  </header>
  
  <!-- Barra de navegação -->
  <nav class="nav">
    <div class="nav-links">
      <a href="/">Início</a>
      <a href="/add_camera">Adicionar Câmera</a>
    </div>
    <div class="user-info">
      <span>Bem-vindo, Admin</span>
      <a href="/logout" class="btn btn-danger">Sair</a>
    </div>
  </nav>
  
  <div class="container">
    <div class="form-container">
      <form action="/add_camera" method="post">
        <div class="form-group">
          <label for="nomecamera">Nome da Câmera:</label>
          <input type="text" id="nomecamera" name="nomecamera" class="form-control" required>
          <small>Nome que identifica a câmera (ex: "Av. Principal")</small>
        </div>
        
        <div class="form-group">
          <label for="ipcamera">Endereço IP da Câmera:</label>
          <input type="text" id="ipcamera" name="ipcamera" class="form-control" required>
          <small>Endereço IP para acesso à câmera (ex: 192.168.1.100)</small>
        </div>
        
        <div class="form-group">
          <label for="protocolo">Protocolo RTSP:</label>
          <select id="protocolo" name="protocolo" class="form-control">
            <option value="tcp">TCP</option>
            <option value="udp">UDP</option>
            <option value="http">HTTP</option>
          </select>
          <small>Protocolo de transporte para o RTSP</small>
        </div>
        
        <div class="form-group">
          <label for="portartsp">Porta RTSP:</label>
          <input type="text" id="portartsp" name="portartsp" class="form-control" value="554">
          <small>Porta padrão é 554</small>
        </div>
        
        <div class="form-group">
          <label for="usuariocamera">Usuário da Câmera:</label>
          <input type="text" id="usuariocamera" name="usuariocamera" class="form-control" required>
          <small>Nome de usuário para autenticação na câmera</small>
        </div>
        
        <div class="form-group">
          <label for="senhacamera">Senha da Câmera:</label>
          <input type="password" id="senhacamera" name="senhacamera" class="form-control" required>
          <small>Senha para autenticação na câmera</small>
        </div>
        
        <div class="form-group">
          <label for="chaveyoutube">Chave de Stream do YouTube:</label>
          <input type="text" id="chaveyoutube" name="chaveyoutube" class="form-control" required>
          <small>Chave para transmissão ao vivo no YouTube</small>
        </div>
        
        <div class="form-actions">
          <button type="submit" class="btn btn-primary">Adicionar Câmera</button>
          <a href="/" class="link">Cancelar</a>
        </div>
      </form>
    </div>
  </div>
</body>
</html>
EOF

# Template para editar câmera
cat > $INSTALL_DIR/views/edit_camera.ejs << EOF
<!DOCTYPE html>
<html lang="pt-br">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Editar Câmera</title>
  <link rel="stylesheet" href="/css/style.css">
</head>
<body>
  <!-- Cabeçalho -->
  <header class="header">
    <h1>Editar Câmera: <%= camera_name %></h1>
  </header>
  
  <!-- Barra de navegação -->
  <nav class="nav">
    <div class="nav-links">
      <a href="/">Início</a>
      <a href="/add_camera">Adicionar Câmera</a>
    </div>
    <div class="user-info">
      <span>Bem-vindo, Admin</span>
      <a href="/logout" class="btn btn-danger">Sair</a>
    </div>
  </nav>
  
  <div class="container">
    <div class="form-container">
      <form action="/edit_camera/<%= camera_name %>" method="post">
        <div class="form-group">
          <label for="ipcamera">Endereço IP da Câmera:</label>
          <input type="text" id="ipcamera" name="ipcamera" class="form-control" value="<%= detalhes.ip %>" required>
        </div>
        
        <div class="form-group">
          <label for="protocolo">Protocolo RTSP:</label>
          <select id="protocolo" name="protocolo" class="form-control">
            <option value="tcp" <%= detalhes.protocolo === 'tcp' ? 'selected' : '' %>>TCP</option>
            <option value="udp" <%= detalhes.protocolo === 'udp' ? 'selected' : '' %>>UDP</option>
            <option value="http" <%= detalhes.protocolo === 'http' ? 'selected' : '' %>>HTTP</option>
          </select>
        </div>
        
        <div class="form-group">
          <label for="portartsp">Porta RTSP:</label>
          <input type="text" id="portartsp" name="portartsp" class="form-control" value="<%= detalhes.portartsp %>" required>
        </div>
        
        <div class="form-group">
          <label for="usuariocamera">Usuário da Câmera:</label>
          <input type="text" id="usuariocamera" name="usuariocamera" class="form-control" value="<%= detalhes.usuario %>" required>
        </div>
        
        <div class="form-group">
          <label for="senhacamera">Senha da Câmera:</label>
          <input type="password" id="senhacamera" name="senhacamera" class="form-control" value="<%= detalhes.senha %>" required>
          <div class="show-password" style="margin-top: 8px;">
            <input type="checkbox" id="showPassword">
            <label for="showPassword" style="display: inline; font-weight: normal;">Mostrar senha</label>
          </div>
        </div>
        
        <div class="form-actions">
          <button type="submit" class="btn btn-primary">Salvar Alterações</button>
          <a href="/" class="link">Cancelar</a>
        </div>
      </form>
    </div>
  </div>
  
  <script>
    // Mostrar/ocultar senha
    document.getElementById('showPassword').addEventListener('change', function() {
      const senhaInput = document.getElementById('senhacamera');
      senhaInput.type = this.checked ? 'text' : 'password';
    });
  </script>
</body>
</html>
EOF

# Template para visualizar logs
cat > $INSTALL_DIR/views/view_logs.ejs << EOF
<!DOCTYPE html>
<html lang="pt-br">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Logs da Câmera: <%= nomecamera %></title>
  <link rel="stylesheet" href="/css/style.css">
  <script src="https://cdnjs.cloudflare.com/ajax/libs/socket.io/4.0.0/socket.io.min.js"></script>
</head>
<body>
  <!-- Cabeçalho -->
  <header class="header">
    <h1>Logs: <%= nomecamera %></h1>
  </header>
  
  <!-- Barra de navegação -->
  <nav class="nav">
    <div class="nav-links">
      <a href="/">Início</a>
      <a href="/add_camera">Adicionar Câmera</a>
    </div>
    <div class="user-info">
      <span>Bem-vindo, Admin</span>
      <a href="/logout" class="btn btn-danger">Sair</a>
    </div>
  </nav>
  
  <div class="container">
    <div class="log-actions">
      <a href="/" class="btn btn-primary">← Voltar</a>
      <form action="/clear_logs/<%= nomecamera %>" method="post" style="display: inline;">
        <button type="submit" class="btn btn-danger" onclick="return confirm('Tem certeza que deseja limpar os logs?');">
          Limpar Logs
        </button>
      </form>
    </div>
    
    <div class="log-container" id="logContainer"></div>
  </div>
  
  <script>
    document.addEventListener('DOMContentLoaded', function() {
      const socket = io();
      const logContainer = document.getElementById('logContainer');
      
      // Conectar ao servidor e iniciar o monitoramento de logs
      socket.on('connect', function() {
        console.log('Conectado ao servidor');
        socket.emit('start_log', { nomecamera: '<%= nomecamera %>' });
      });
      
      // Receber atualizações de log
      socket.on('log_update', function(data) {
        if (data.type === 'status') {
          // Exibir status da câmera se necessário
          console.log('Status da câmera:', data.content);
        } else {
          // Adicionar linha de log
          const logLine = document.createElement('div');
          logLine.classList.add('log-line');
          
          // Aplicar classe baseada no tipo
          if (data.type) {
            logLine.classList.add(\`log-\${data.type}\`);
          }
          
          // Adicionar timestamp se disponível
          if (data.timestamp) {
            const timestamp = document.createElement('span');
            timestamp.classList.add('log-timestamp');
            timestamp.style.color = '#888';
            timestamp.style.marginRight = '10px';
            timestamp.textContent = new Date(data.timestamp).toLocaleTimeString();
            logLine.appendChild(timestamp);
          }
          
          // Adicionar conteúdo do log
          const content = document.createElement('span');
          content.textContent = data.content;
          logLine.appendChild(content);
          
          // Colorir linhas com base no conteúdo
          const text = data.content.toLowerCase();
          if (text.includes('erro') || text.includes('falha') || text.includes('error')) {
            logLine.style.color = '#ff6b6b';
          } else if (text.includes('aviso') || text.includes('warning')) {
            logLine.style.color = '#ffd166';
          } else if (text.includes('sucesso') || text.includes('iniciado')) {
            logLine.style.color = '#06d6a0';
          }
          
          logContainer.appendChild(logLine);
          
          // Auto-scroll para o final
          logContainer.scrollTop = logContainer.scrollHeight;
        }
      });
      
      // Detectar desconexão
      socket.on('disconnect', function() {
        const logLine = document.createElement('div');
        logLine.classList.add('log-line');
        logLine.style.color = '#ff6b6b';
        logLine.textContent = '--- Conexão com o servidor perdida. Recarregue a página para reconectar. ---';
        logContainer.appendChild(logLine);
      });
    });
  </script>
</body>
</html>
EOF

# Iniciar e ativar o serviço
print_message "Iniciando o serviço..."
systemctl enable camera-manager.service
systemctl start camera-manager.service

# Informações finais
print_message "Instalação concluída!"
print_message "O sistema está rodando em http://localhost:3000"
print_message "Usuário: admin"
print_message "Senha: adminpass"

# Verificar status do serviço
systemctl status camera-manager.service --no-pager

# Instruções finais
echo
print_message "Para acessar o sistema, abra o navegador e acesse: http://$(hostname -I | awk '{print $1}'):3000"
print_message "Para verificar os logs do serviço: sudo journalctl -u camera-manager -f"
print_message "Para reiniciar o serviço: sudo systemctl restart camera-manager"
print_message "Para parar o serviço: sudo systemctl stop camera-manager"