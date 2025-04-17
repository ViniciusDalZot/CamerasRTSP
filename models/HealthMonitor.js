/**
 * HealthMonitor.js
 * Monitora a saúde do sistema e das câmeras
 */
const os = require('os');
const fs = require('fs');
const { execSync } = require('child_process');
const CameraManager = require('./CameraManager');
const LogManager = require('./LogManager');
const config = require('../config/default');

class HealthMonitor {
  constructor() {
    this.basePath = config.basePath;
    this.healthData = {
      system: {},
      cameras: {},
      lastUpdate: null
    };
  }

  /**
   * Coleta informações de saúde do sistema
   */
  async collectSystemHealth() {
    try {
      // Informações do sistema
      const cpuUsage = this.getCpuUsage();
      const memoryUsage = this.getMemoryUsage();
      const diskUsage = this.getDiskUsage();
      const uptime = os.uptime();
      const loadAvg = os.loadavg();
      
      // Informações do processo Node.js
      const nodeProcess = process.memoryUsage();
      
      // Informações de rede
      const networkInterfaces = os.networkInterfaces();
      
      this.healthData.system = {
        cpu: cpuUsage,
        memory: memoryUsage,
        disk: diskUsage,
        uptime,
        loadAvg,
        nodeProcess,
        networkInterfaces,
        timestamp: new Date().toISOString()
      };
      
      return this.healthData.system;
    } catch (error) {
      console.error(`Erro ao coletar informações de saúde do sistema: ${error.message}`);
      return {
        error: error.message,
        timestamp: new Date().toISOString()
      };
    }
  }

  /**
   * Coleta informações de saúde das câmeras
   */
  async collectCamerasHealth() {
    try {
      const cameras = CameraManager.listCameras();
      const camerasHealth = {};
      
      for (const camera of cameras) {
        const details = CameraManager.getCameraDetails(camera);
        if (!details) continue;
        
        const pingResult = await CameraManager.pingCamera(details.ip);
        const status = await LogManager.getCameraStatus(camera);
        const logPath = LogManager.getLogFile(camera);
        
        // Verificar tamanho do arquivo de log
        let logSize = 0;
        if (logPath && fs.existsSync(logPath)) {
          const stats = fs.statSync(logPath);
          logSize = stats.size;
        }
        
        // Verificar processos FFMPEG para esta câmera
        let ffmpegProcesses = [];
        try {
          const output = execSync(`ps -ef | grep ffmpeg | grep "${details.ip}" | grep -v grep`).toString();
          ffmpegProcesses = output.split('\n').filter(Boolean).map(line => {
            const parts = line.trim().split(/\s+/);
            return {
              pid: parts[1],
              startTime: parts[4] + ' ' + parts[5],
              command: parts.slice(7).join(' ')
            };
          });
        } catch (error) {
          // Nenhum processo encontrado, ignorar erro
        }
        
        camerasHealth[camera] = {
          details,
          ping: pingResult,
          status,
          logSize,
          ffmpegProcesses,
          lastCheck: new Date().toISOString()
        };
      }
      
      this.healthData.cameras = camerasHealth;
      this.healthData.lastUpdate = new Date().toISOString();
      
      return camerasHealth;
    } catch (error) {
      console.error(`Erro ao coletar informações de saúde das câmeras: ${error.message}`);
      return {
        error: error.message,
        timestamp: new Date().toISOString()
      };
    }
  }

  /**
   * Obtém todas as informações de saúde
   */
  async getFullHealthReport() {
    await this.collectSystemHealth();
    await this.collectCamerasHealth();
    
    return this.healthData;
  }

  /**
   * Obtém informações de uso da CPU
   */
  getCpuUsage() {
    try {
      // No Linux, obter informações mais precisas do /proc/stat
      if (os.platform() === 'linux') {
        const output = execSync('top -bn1 | grep "Cpu(s)" | sed "s/.*, *\\([0-9.]*\\)%* id.*/\\1/" | awk \'{print 100 - $1}\'').toString().trim();
        return {
          usage: parseFloat(output),
          cores: os.cpus().length
        };
      }
      
      // Para outros sistemas, usar informações do OS
      const cpus = os.cpus();
      let totalIdle = 0;
      let totalTick = 0;
      
      cpus.forEach(cpu => {
        for (const type in cpu.times) {
          totalTick += cpu.times[type];
        }
        totalIdle += cpu.times.idle;
      });
      
      const usage = 100 - (totalIdle / totalTick * 100);
      
      return {
        usage,
        cores: cpus.length
      };
    } catch (error) {
      return {
        error: error.message
      };
    }
  }

  /**
   * Obtém informações de uso de memória
   */
  getMemoryUsage() {
    const totalMem = os.totalmem();
    const freeMem = os.freemem();
    const usedMem = totalMem - freeMem;
    
    return {
      total: this.formatBytes(totalMem),
      free: this.formatBytes(freeMem),
      used: this.formatBytes(usedMem),
      usedPercentage: (usedMem / totalMem * 100).toFixed(2)
    };
  }

  /**
   * Obtém informações de uso de disco
   */
  getDiskUsage() {
    try {
      if (os.platform() === 'linux') {
        const output = execSync('df -h / | tail -1').toString();
        const parts = output.split(/\s+/);
        
        return {
          filesystem: parts[0],
          size: parts[1],
          used: parts[2],
          available: parts[3],
          usedPercentage: parts[4]
        };
      }
      
      // Para outros sistemas, retornar placeholder
      return {
        info: 'Informações de disco não disponíveis para este sistema operacional'
      };
    } catch (error) {
      return {
        error: error.message
      };
    }
  }

  /**
   * Formata bytes para unidades legíveis
   */
  formatBytes(bytes, decimals = 2) {
    if (bytes === 0) return '0 Bytes';
    
    const k = 1024;
    const dm = decimals < 0 ? 0 : decimals;
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];
    
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    
    return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
  }

  /**
   * Verifica se há problemas críticos
   */
  checkForCriticalIssues() {
    const issues = [];
    
    // Verificar uso de CPU
    if (this.healthData.system.cpu && this.healthData.system.cpu.usage > 90) {
      issues.push({
        type: 'critical',
        component: 'system',
        message: `Uso de CPU alto: ${this.healthData.system.cpu.usage.toFixed(2)}%`
      });
    }
    
    // Verificar uso de memória
    if (this.healthData.system.memory && parseFloat(this.healthData.system.memory.usedPercentage) > 90) {
      issues.push({
        type: 'critical',
        component: 'system',
        message: `Uso de memória alto: ${this.healthData.system.memory.usedPercentage}%`
      });
    }
    
    // Verificar espaço em disco
    if (this.healthData.system.disk && this.healthData.system.disk.usedPercentage) {
      const diskUsage = parseInt(this.healthData.system.disk.usedPercentage.replace('%', ''));
      if (diskUsage > 90) {
        issues.push({
          type: 'critical',
          component: 'system',
          message: `Espaço em disco baixo: ${this.healthData.system.disk.usedPercentage} usado`
        });
      }
    }
    
    // Verificar problemas com câmeras
    for (const [camera, health] of Object.entries(this.healthData.cameras)) {
      // Verificar se a câmera está offline
      if (health.ping === 'Sem Comunicação') {
        issues.push({
          type: 'warning',
          component: 'camera',
          camera,
          message: `Câmera ${camera} está offline`
        });
      }
      
      // Verificar se o streaming está com problemas
      if (health.status && health.status.running && health.ffmpegProcesses.length === 0) {
        issues.push({
          type: 'critical',
          component: 'camera',
          camera,
          message: `Câmera ${camera} reporta streaming ativo mas nenhum processo FFMPEG foi encontrado`
        });
      }
      
      // Verificar tamanho do log
      if (health.logSize > 10 * 1024 * 1024) { // 10 MB
        issues.push({
          type: 'warning',
          component: 'camera',
          camera,
          message: `Log da câmera ${camera} é muito grande (${this.formatBytes(health.logSize)})`
        });
      }
    }
    
    return issues;
  }
}

module.exports = new HealthMonitor();