/**
 * Funcionalidades JavaScript do lado do cliente
 */

// Obter referência ao objeto socket.io quando o DOM estiver carregado
document.addEventListener('DOMContentLoaded', function() {
    // Verificar se socket.io está disponível
    if (typeof io !== 'undefined') {
      const socket = io();
      
      // Inicializar monitoramento de câmeras se estiver na página inicial
      if (window.location.pathname === '/') {
        initCameraMonitoring(socket);
      }
      
      // Inicializar visualizador de logs se estiver na página de logs
      if (window.location.pathname.includes('/view_logs/')) {
        initLogViewer(socket);
      }
    } else {
      console.error('Socket.io não está disponível');
    }
    
    // Inicializar validadores de formulário
    initFormValidators();
  });
  
  /**
   * Inicializa o monitoramento de status das câmeras
   */
  function initCameraMonitoring(socket) {
    // Atualizar status das câmeras a cada 30 segundos
    setInterval(() => {
      socket.emit('monitor_cameras');
    }, 30000);
    
    // Receber atualizações de status
    socket.on('camera_status_update', function(data) {
      const cameras = data.cameras;
      
      cameras.forEach(camera => {
        const cardElements = document.querySelectorAll('.camera-card');
        
        cardElements.forEach(card => {
          const nameElement = card.querySelector('h2');
          if (nameElement && nameElement.textContent === camera.name) {
            const statusElement = card.querySelector('.status');
            
            if (statusElement) {
              if (camera.ping === 'Sem Comunicação') {
                statusElement.textContent = `Offline (${camera.ping})`;
                statusElement.className = 'status offline';
              } else {
                statusElement.textContent = `Online (${camera.ping})`;
                statusElement.className = 'status online';
              }
            }
          }
        });
      });
    });
  }
  
  /**
   * Inicializa o visualizador de logs
   */
  function initLogViewer(socket) {
    const logContainer = document.getElementById('logContainer');
    if (!logContainer) return;
    
    // Extrair nome da câmera da URL
    const urlParts = window.location.pathname.split('/');
    const nomecamera = urlParts[urlParts.length - 1];
    
    // Conectar ao servidor e iniciar o monitoramento de logs
    socket.on('connect', function() {
      console.log('Conectado ao servidor');
      socket.emit('start_log', { nomecamera });
    });
    
    // Receber atualizações de log
    socket.on('log_update', function(data) {
      const logLine = document.createElement('div');
      logLine.classList.add('log-line');
      logLine.textContent = data.log;
      logContainer.appendChild(logLine);
      
      // Auto-scroll para o final
      logContainer.scrollTop = logContainer.scrollHeight;
    });
    
    // Detectar desconexão
    socket.on('disconnect', function() {
      const logLine = document.createElement('div');
      logLine.classList.add('log-line');
      logLine.style.color = '#ff6b6b';
      logLine.textContent = '--- Conexão com o servidor perdida. Recarregue a página para reconectar. ---';
      logContainer.appendChild(logLine);
    });
  }
  
  /**
   * Inicializa validadores de formulário
   */
  function initFormValidators() {
    // Validação do formulário de adição de câmera
    const addCameraForm = document.querySelector('form[action="/add_camera"]');
    if (addCameraForm) {
      addCameraForm.addEventListener('submit', validateCameraForm);
    }
    
    // Validação do formulário de edição de câmera
    const editCameraForm = document.querySelector('form[action^="/edit_camera/"]');
    if (editCameraForm) {
      editCameraForm.addEventListener('submit', validateCameraForm);
      
      // Toggle para mostrar/ocultar senha
      const showPasswordCheckbox = document.getElementById('showPassword');
      if (showPasswordCheckbox) {
        showPasswordCheckbox.addEventListener('change', function() {
          const senhaInput = document.getElementById('senhacamera');
          senhaInput.type = this.checked ? 'text' : 'password';
        });
      }
    }
  }
  
  /**
   * Valida formulários de câmera
   */
  function validateCameraForm(event) {
    // Validar IP
    const ipInput = document.getElementById('ipcamera');
    if (ipInput) {
      const ipPattern = /^(\d{1,3}\.){3}\d{1,3}$/;
      
      if (!ipPattern.test(ipInput.value)) {
        alert('Por favor, insira um endereço IP válido.');
        event.preventDefault();
        return false;
      }
      
      // Verificar se cada octeto está entre 0 e 255
      const octetos = ipInput.value.split('.');
      for (const octeto of octetos) {
        const num = parseInt(octeto, 10);
        if (num < 0 || num > 255) {
          alert('Por favor, insira um endereço IP válido (cada número deve estar entre 0 e 255).');
          event.preventDefault();
          return false;
        }
      }
    }
    
    // Validar porta
    const portInput = document.getElementById('portartsp');
    if (portInput) {
      const port = parseInt(portInput.value, 10);
      if (isNaN(port) || port < 1 || port > 65535) {
        alert('Por favor, insira um número de porta válido (1-65535).');
        event.preventDefault();
        return false;
      }
    }
    
    return true;
  }