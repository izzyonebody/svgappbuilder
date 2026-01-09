const { app, BrowserWindow } = require("electron");
const { spawn } = require("child_process");
const path = require("path");
const isDev = require("electron-is-dev");

let backendProcess = null;

function startBackend() {
  let exePath;
  if (isDev) {
    exePath = path.join(__dirname, "..", "backend", "venv", "Scripts", "python.exe"); // dev path placeholder
    console.log("Dev mode: please run backend separately (uvicorn).");
    return;
  } else {
    exePath = path.join(process.resourcesPath, "backend", "backend.exe");
  }

  try {
    backendProcess = spawn(exePath, [], { windowsHide: true });
    backendProcess.stdout.on("data", (data) => {
      console.log("backend:", data.toString());
    });
    backendProcess.stderr.on("data", (data) => {
      console.error("backend-err:", data.toString());
    });
  } catch (e) {
    console.error("Failed to start backend exe:", e);
  }
}

function createWindow() {
  const win = new BrowserWindow({
    width: 1200,
    height: 900,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true
    }
  });

  if (isDev) {
    win.loadURL("http://localhost:3000");
  } else {
    win.loadFile(path.join(__dirname, "build", "index.html"));
  }
}

app.on("ready", () => {
  startBackend();
  createWindow();
});

app.on("before-quit", () => {
  if (backendProcess) {
    backendProcess.kill();
  }
});
