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
const CameraManager = require('./CameraManager');

class LogManager {
  constructor() {
    this.basePath = config.basePath;
    this.activeStreams = {};
  }

  /**
   * Obtém o caminho do arquivo de log de uma câmera
   */
  getLogFile(nomecamera) {
    const logPath = path.join(this.basePath, `${nomecamera}.log`);
    if (!fs.existsSync(logPath)) {
      // Criar o arquivo de log se não existir
      try {
        fs.writeFileSync(logPath, '');
      } catch (error) {
        console.error(`Erro ao criar arquivo de log: ${error.message}`);
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
      const { stdout } = await execPromise(`tail -n ${lines} "${logPath}"`);
      return stdout.split('\n').filter(Boolean);
    } catch (error) {
      console.error(`Erro ao obter logs: ${error.message}`);
      return ['Erro ao obter logs'];
    }
  }

  /**
   * Segue o arquivo de log em tempo real (para uso com WebSockets)
   */
  async followLog(nomecamera, callback) {
    const logPath = this.getLogFile(nomecamera);
    if (!logPath) {
      callback({
        type: 'error',
        content: 'Arquivo de log não encontrado'
      });
      return null;
    }

    // Obter detalhes da câmera para encontrar o IP
    const cameraDetails = CameraManager.getCameraDetails(nomecamera);
    if (!cameraDetails || !cameraDetails.ip) {
      callback({
        type: 'error',
        content: 'Detalhes da câmera não encontrados'
      });
      return null;
    }

    const ipcamera = cameraDetails.ip;

    // Verificar se já existe um processo ativo para esta câmera
    if (this.activeStreams[nomecamera]) {
      this.activeStreams[nomecamera].kill();
      delete this.activeStreams[nomecamera];
    }

    // Obter o status atual da câmera
    try {
      const status = await this.getCameraStatus(nomecamera);
      callback({
        type: 'status',
        content: status
      });
    } catch (error) {
      console.error(`Erro ao obter status: ${error.message}`);
    }

    const tail = spawn('tail', ['-f', logPath]);
    this.activeStreams[nomecamera] = tail;
    
    tail.stdout.on('data', (data) => {
      data.toString().split('\n').filter(Boolean).forEach(line => {
        callback({
          type: 'log',
          content: line,
          timestamp: new Date().toISOString()
        });
      });
    });
    
    tail.stderr.on('data', (data) => {
      console.error(`Erro ao seguir log: ${data}`);
      callback({
        type: 'error',
        content: `Erro: ${data}`
      });
    });
    
    tail.on('close', (code) => {
      callback({
        type: 'system',
        content: `Monitoramento de logs encerrado (código: ${code})`
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
      // Obter detalhes da câmera para encontrar o IP
      const cameraDetails = CameraManager.getCameraDetails(nomecamera);
      if (!cameraDetails || !cameraDetails.ip) {
        return {
          running: false,
          message: 'Detalhes da câmera não encontrados',
          error: 'IP da câmera não disponível'
        };
      }

      const ipcamera = cameraDetails.ip;

      // Verificar se existe um processo ffmpeg para esta câmera
      const { stdout } = await execPromise(`ps aux | grep ffmpeg | grep "${ipcamera}" | grep -v grep | wc -l`);
      const count = parseInt(stdout.trim(), 10);
      
      if (count > 0) {
        return {
          running: true,
          message: 'Transmissão ativa',
          since: await this.getStreamStartTime(ipcamera)
        };
      } else {
        return {
          running: false,
          message: 'Transmissão inativa',
          lastRun: await this.getLastRunTime(nomecamera)
        };
      }
    } catch (error) {
      console.error(`Erro ao verificar status da câmera: ${error.message}`);
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
  async getStreamStartTime(ipcamera) {
    try {
      const { stdout } = await execPromise(`ps -o lstart= -p $(ps aux | grep ffmpeg | grep "${ipcamera}" | grep -v grep | awk '{print $2}' | head -1)`);
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
