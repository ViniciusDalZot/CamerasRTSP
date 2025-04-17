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