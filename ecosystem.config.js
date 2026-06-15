module.exports = {
  apps: [{
    name: 'crystal-api',
    script: './backend/server.js',
    instances: 1,
    exec_mode: 'fork',
    max_memory_restart: '500M',
    error_file: './logs/error.log',
    out_file: './logs/out.log',
    merge_logs: true,
    log_date_format: 'YYYY-MM-DD HH:mm:ss',
    max_restarts: 5,
    restart_delay: 10000,
    env: {
      NODE_ENV: 'production'
    }
  }]
};
