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
const CronManager = require('../models/CronManager');

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
    const script = `#! /bin/bash
date=$(date "+DATE: %d/%m/%Y %T")
ipcamera='${ipcamera}'
nomecamera='${nomecamera}'
usuariocamera='${usuariocamera}'
senhacamera='${senhacamera}'
chaveyoutube='${chaveyoutube}'
processocamera=$(ps -aux |grep -v grep | grep -o "${ipcamera}" | wc -l | grep -v grep;)
processomanu=$(ps -ef | grep "${chaveyoutube}" | grep 'twspeed' | grep -v grep | wc -l | grep -v grep;)
portartsp='${portartsp}'
protocolo='${protocolo}'
function SteamingCamera () {
    log_file="${this.basePath}$nomecamera.log"
    if [ "$processocamera" -ge "1" ]; then
        echo "" >> "$log_file"
        ps -ef | grep $chaveyoutube | grep 'manutencao' | grep -v grep | awk '{print $2}' | xargs kill -9;
    else
        ps -ef | grep "$chaveyoutube" | grep 'manutencao' | grep -v grep | awk '{print $2}' | xargs kill -9;
        echo "" >> "$log_file"
        nohup ffmpeg -f lavfi -i anullsrc -rtsp_transport $protocolo -i "rtsp://$usuariocamera:$senhacamera@$ipcamera:$portartsp/cam/realmonitor?channel=1&subtype=0" \\
-vf "movie=${config.camera.logoPath} [watermark]; [in][watermark] overlay=10:10" \\
-tune zerolatency -preset medium -pix_fmt yuv420p \\
-c:v libx264 -x264opts keyint=48:min-keyint=48:no-scenecut -b:v 2000k \\
-c:a aac -strict experimental -f flv rtmps://a.rtmp.youtube.com/live2/$chaveyoutube >> "$log_file" 2>&1 &
    fi
}

function SteamingManutencao () {
    if [ "$processomanu" -ge "1" ]; then
        ps -ef | grep "$ipcamera" | grep -v grep | awk '{print $2}' | xargs kill -9;
        echo "$date - Camera da $nomecamera com IP $ipcamera | Usuario: $usuariocamera | Senha: $senhacamera |  esta inacessivel" >> ${this.basePath}$nomecamera.log
    else
        ps -ef | grep "$ipcamera" | grep -v grep | awk '{print $2}' | xargs kill -9;
        echo "$date - Camera da $nomecamera com IP $ipcamera| Usuario: $usuariocamera | Senha: $senhacamera |  esta inacessivel" >> ${this.basePath}$nomecamera.log
        nohup ffmpeg -stream_loop -1 -re -i ${config.camera.maintenanceVideo} -c:v libx264 -preset ultrafast -bufsize 5 -r 30 -b:v 500k -maxrate 1000k -f flv rtmps://a.rtmp.youtube.com/live2/$chaveyoutube &> /dev/null &
    fi
}
ping=$(ping -c 2 "$ipcamera" | grep 'received' | awk -F',' '{print $2}' | awk '{print $1}');
if [ "$ping" -ge 1 ]; then
    SteamingCamera;
else
    SteamingManutencao;
fi`;

const scriptPath = path.join(this.basePath, `${nomecamera}.sh`);
fs.writeFileSync(scriptPath, script);
fs.chmodSync(scriptPath, 0o755);

return CronManager.addCronJob(nomecamera);

}

  /**
   * Inicia o streaming para a câmera
   */
 /**
 * Inicia o streaming para a câmera em background
 */
 startStream(nomecamera) {
  console.log(`Iniciando stream para ${nomecamera}`);
  const scriptPath = path.join(this.basePath, `${nomecamera}.sh`);
  console.log(`Caminho do script: ${scriptPath}`);
  
  if (fs.existsSync(scriptPath)) {
    console.log(`Script encontrado`);
    try {
      console.log(`Executando comando: nohup bash ${scriptPath} > /dev/null 2>&1 &`);
      execSync(`nohup bash ${scriptPath} > /dev/null 2>&1 &`);
      console.log(`Comando executado com sucesso`);
      return true;
    } catch (error) {
      console.error(`Erro ao iniciar stream: ${error.message}`);
      return false;
    }
  } else {
    console.log(`Script não encontrado`);
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
      await exec(`ps -ef | grep "${detalhes.ip}" | grep -v grep | awk '{print $2}' | xargs kill -9 2>/dev/null || true`);
      
      // Garante que ffmpeg seja encerrado
      await exec('pkill -f ffmpeg || true');
      
      return true;
    } catch (error) {
      console.error(`Erro ao parar stream: ${error.message}`);
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
      return `${parseFloat(res.time).toFixed(2)} ms`;
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
      console.error(`Erro ao listar câmeras: ${error.message}`);
      return [];
    }
  }

  /**
   * Obtém detalhes de uma câmera específica
   */
  getCameraDetails(nomecamera) {
    const scriptPath = path.join(this.basePath, `${nomecamera}.sh`);
    
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
      console.error(`Erro ao obter detalhes da câmera: ${error.message}`);
      return null;
    }
  }

  /**
   * Atualiza informações de uma câmera
   */
  updateCameraDetails(nomecamera, novosDetalhes) {
    const scriptPath = path.join(this.basePath, `${nomecamera}.sh`);
    
    if (!fs.existsSync(scriptPath)) {
      return false;
    }
    
    try {
      let content = fs.readFileSync(scriptPath, 'utf8');
      
      // Atualiza cada campo
      for (const [key, value] of Object.entries(novosDetalhes)) {
        if (value !== undefined) {
          // Cria um padrão regex que corresponde à definição da variável
          const pattern = new RegExp(`${key}='[^']+'`);
          content = content.replace(pattern, `${key}='${value}'`);
        }
      }
      
      fs.writeFileSync(scriptPath, content);
      return true;
    } catch (error) {
      console.error(`Erro ao atualizar detalhes da câmera: ${error.message}`);
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
      const scriptPath = path.join(this.basePath, `${nomecamera}.sh`);
      if (fs.existsSync(scriptPath)) {
        fs.unlinkSync(scriptPath);
      }
      
      // Remove do crontab
      const currentCrontab = execSync('crontab -l').toString();
      const newCrontab = currentCrontab
        .split('\n')
        .filter(line => !line.includes(`/etc/camerastwspeed/${nomecamera}.sh`))
        .join('\n');
      
      execSync(`echo "${newCrontab}" | crontab -`);
      
      return true;
    } catch (error) {
      console.error(`Erro ao remover câmera: ${error.message}`);
      return false;
    }
  }
}

module.exports = new CameraManager();