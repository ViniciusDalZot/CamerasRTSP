/**
 * Configurações globais da aplicação
 */
module.exports = {
    // Diretório base para arquivos de câmeras
    basePath: '/etc/camerastwspeed/',
    
    // Configurações do servidor
    server: {
      port: process.env.PORT || 3000,
      secret: process.env.SECRET_KEY || 'camera-manager-secret-key'
    },
    
    // Configurações de autenticação
    auth: {
      users: {
        admin: {
          password: process.env.ADMIN_PASSWORD || 'twspeed'
        }
      }
    },
    
    // Configurações padrão para câmeras
    camera: {
      defaultProtocol: 'tcp',
      defaultPort: '554',
      ffmpegPath: '/usr/bin/ffmpeg',
      logoPath: '/etc/camerastwspeed/logo1.png',
      maintenanceVideo: '/etc/camerastwspeed/twspeed.mp4'
    }
  };