module.exports = {
  apps: [
    {
      name: "katiya-api",
      script: "./dist/src/main.js",
      cwd: "/home/katiyarms/katiyastation/katiyastations/backend",
      instances: 1,
      exec_mode: "fork",
      autorestart: true,
      watch: false,
      max_memory_restart: "500M",
      env: {
        NODE_ENV: "production"
      }
    }
  ]
};