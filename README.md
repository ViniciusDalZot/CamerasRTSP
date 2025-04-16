# Sistema de Gerenciamento de Câmeras RTSP

Um sistema completo para gerenciar câmeras IP com RTSP e transmitir fluxos de vídeo para o YouTube, desenvolvido em Node.js.

## Características

- Adicionar, editar e remover câmeras RTSP
- Iniciar/parar transmissão para o YouTube
- Monitoramento de status de câmeras em tempo real
- Visualização de logs em tempo real
- Opção de fallback para vídeo de manutenção quando uma câmera fica offline
- Interface responsiva e amigável

## Requisitos

- Node.js v14.x ou superior
- FFmpeg instalado no sistema
- Acesso às câmeras IP com suporte a RTSP
- Conta do YouTube com chave de stream para transmissões ao vivo

## Instalação

1. Clone o repositório:
   ```bash
   git clone https://github.com/seu-usuario/camera-manager.git
   cd camera-manager
   ```

2. Instale as dependências:
   ```bash
   npm install
   ```

3. Configure o ambiente:
   ```bash
   # Crie o diretório para armazenar os scripts e logs das câmeras
   sudo mkdir -p /etc/camerastwspeed
   sudo chmod 755 /etc/camerastwspeed
   
   # Copie o vídeo de manutenção para a pasta
   cp resources/twspeed.mp4 /etc/camerastwspeed/
   
   # Copie a imagem para marca d'água
   cp resources/logo1.png /etc/camerastwspeed/
   ```

4. Inicie o servidor:
   ```bash
   npm start
   ```

5. Acesse a aplicação em:
   ```
   http://localhost:3000
   ```

6. Faça login com as credenciais:
   - Usuário: admin
   - Senha: adminpass

## Estrutura do Projeto

```
camera-manager/
├── config/
│   └── default.js          # Configurações globais
├── models/
│   ├── Auth.js             # Gerenciamento de autenticação
│   ├── CameraManager.js    # Gerenciamento de câmeras
│   └── LogManager.js       # Gerenciamento de logs
├── public/
│   ├── css/
│   │   └── style.css       # Estilos CSS
│   └── js/
│       └── main.js         # JavaScript do cliente
├── routes/
│   └── index.js            # Rotas da aplicação
├── views/
│   ├── add_camera.ejs      # Formulário para adicionar câmera
│   ├── edit_camera.ejs     # Formulário para editar câmera
│   ├── index.ejs           # Página principal
│   ├── login.ejs           # Página de login
│   └── view_logs.ejs       # Visualizador de logs
├── app.js                  # Arquivo principal da aplicação
└── package.json            # Dependências
```

## Configuração de Câmeras

Para cada câmera, você precisará das seguintes informações:

- Nome da câmera (para identificação)
- Endereço IP da câmera
- Porta RTSP (geralmente 554)
- Protocolo de transporte (TCP, UDP ou HTTP)
- Usuário e senha para acesso à câmera
- Chave de stream do YouTube

## Funcionamento

O sistema cria um script shell para cada câmera adicionada. Esse script:

1. Verifica a disponibilidade da câmera usando ping
2. Se a câmera estiver online:
   - Inicia a transmissão do fluxo RTSP para o YouTube usando FFMPEG
   - Adiciona uma marca d'água à transmissão
3. Se a câmera estiver offline:
   - Transmite um vídeo de manutenção para o canal do YouTube

Os scripts são executados a cada 20 minutos via cron para garantir que a transmissão continue mesmo após reinicializações.

## Segurança

- As senhas das câmeras são armazenadas em texto claro nos scripts shell.
- Recomenda-se implementar criptografia em uma versão de produção.
- Restrinja o acesso à pasta /etc/camerastwspeed apenas a usuários autorizados.

## Licença

Este projeto está licenciado sob a licença MIT - veja o arquivo LICENSE para detalhes.