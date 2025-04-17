/**
 * CronManager.js
 * Gerencia operações relacionadas ao agendamento de câmeras via crontab
 */
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const config = require('../config/default');

class CronManager {
  constructor() {
    this.basePath = config.basePath;
  }

  /**
   * Adiciona um job do crontab para a câmera
   */
  addCronJob(nomecamera, interval = '*/20 * * * *') {
    try {
      const scriptPath = path.join(this.basePath, `${nomecamera}.sh`);
      
      // Verifica se o script existe
      if (!fs.existsSync(scriptPath)) {
        console.error(`Script não encontrado: ${scriptPath}`);
        return false;
      }
      
      // Formata o comando cron
      const cronCommand = `${interval} ${scriptPath} >> ${this.basePath}${nomecamera}.log 2>&1`;
      
      // Obtém o crontab atual
      let currentCrontab = '';
      try {
        currentCrontab = execSync('crontab -l').toString();
      } catch (error) {
        // Se o crontab não existir, começamos com um vazio
        currentCrontab = '';
      }
      
      // Verifica se o job já existe
      if (currentCrontab.includes(scriptPath)) {
        // Remove o job existente
        const lines = currentCrontab.split('\n');
        const filteredLines = lines.filter(line => !line.includes(scriptPath));
        currentCrontab = filteredLines.join('\n');
      }
      
      // Adiciona o novo job
      const newCrontab = currentCrontab.trim() + '\n' + cronCommand + '\n';
      
      // Atualiza o crontab
      fs.writeFileSync('/tmp/crontab.txt', newCrontab);
      execSync('crontab /tmp/crontab.txt');
      fs.unlinkSync('/tmp/crontab.txt');
      
      return true;
    } catch (error) {
      console.error(`Erro ao adicionar job ao crontab: ${error.message}`);
      return false;
    }
  }

  /**
   * Remove um job do crontab para a câmera
   */
  removeCronJob(nomecamera) {
    try {
      const scriptPath = path.join(this.basePath, `${nomecamera}.sh`);
      
      // Obtém o crontab atual
      let currentCrontab = '';
      try {
        currentCrontab = execSync('crontab -l').toString();
      } catch (error) {
        // Se o crontab não existir, não há nada para remover
        return true;
      }
      
      // Verifica se o job existe
      if (!currentCrontab.includes(scriptPath)) {
        return true;
      }
      
      // Remove o job
      const lines = currentCrontab.split('\n');
      const filteredLines = lines.filter(line => !line.includes(scriptPath));
      const newCrontab = filteredLines.join('\n');
      
      // Atualiza o crontab
      fs.writeFileSync('/tmp/crontab.txt', newCrontab);
      execSync('crontab /tmp/crontab.txt');
      fs.unlinkSync('/tmp/crontab.txt');
      
      return true;
    } catch (error) {
      console.error(`Erro ao remover job do crontab: ${error.message}`);
      return false;
    }
  }

  /**
   * Atualiza o intervalo de execução do job
   */
  updateCronInterval(nomecamera, interval) {
    // Remove o job antigo
    this.removeCronJob(nomecamera);
    
    // Adiciona o job com o novo intervalo
    return this.addCronJob(nomecamera, interval);
  }

  /**
   * Obtém o status do cron para a câmera
   */
  getCronStatus(nomecamera) {
    try {
      const scriptPath = path.join(this.basePath, `${nomecamera}.sh`);
      
      // Obtém o crontab atual
      let currentCrontab = '';
      try {
        currentCrontab = execSync('crontab -l').toString();
      } catch (error) {
        // Se o crontab não existir, não há nada para verificar
        return {
          enabled: false,
          interval: null
        };
      }
      
      // Procura o job da câmera
      const lines = currentCrontab.split('\n');
      const jobLine = lines.find(line => line.includes(scriptPath));
      
      if (!jobLine) {
        return {
          enabled: false,
          interval: null
        };
      }
      
      // Extrai o intervalo
      const intervalPart = jobLine.split(scriptPath)[0].trim();
      
      return {
        enabled: true,
        interval: intervalPart
      };
    } catch (error) {
      console.error(`Erro ao verificar status do cron: ${error.message}`);
      return {
        enabled: false,
        interval: null,
        error: error.message
      };
    }
  }

  /**
   * Lista todos os jobs de câmeras no crontab
   */
  listAllCronJobs() {
    try {
      // Obtém o crontab atual
      let currentCrontab = '';
      try {
        currentCrontab = execSync('crontab -l').toString();
      } catch (error) {
        // Se o crontab não existir, não há nada para listar
        return [];
      }
      
      // Filtra apenas os jobs de câmeras
      const lines = currentCrontab.split('\n');
      const cameraJobs = lines.filter(line => line.includes(this.basePath) && line.includes('.sh'));
      
      // Extrai informações de cada job
      return cameraJobs.map(job => {
        const scriptPathMatch = job.match(new RegExp(`${this.basePath}([\\w-]+)\\.sh`));
        if (!scriptPathMatch) return null;
        
        const nomecamera = scriptPathMatch[1];
        const intervalPart = job.split(this.basePath)[0].trim();
        
        return {
          camera: nomecamera,
          interval: intervalPart,
          command: job
        };
      }).filter(Boolean);
    } catch (error) {
      console.error(`Erro ao listar jobs do crontab: ${error.message}`);
      return [];
    }
  }
}

module.exports = new CronManager();