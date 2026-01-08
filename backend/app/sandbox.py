import subprocess
import uuid
import os
import shutil

def run_preview(container_image="node:18-alpine", code_dir="/code", timeout=30):
    """
    Runs a sandboxed container that serves the generated preview.
    This is a minimal example that mounts code_dir into the container and runs a static server.
    In production, make sure to restrict network and run as unprivileged user.
    """
    run_id = str(uuid.uuid4())[:8]
    container_name = f"svgbuilder_preview_{run_id}"
    # Example: use http-server to serve a folder; assume code_dir contains a prepared build
    cmd = [
        "docker", "run", "--rm", "--name", container_name,
        "--network", "none",  # disable network
        "-v", f"{code_dir}:/srv:ro",
        "-w", "/srv",
        container_image,
        "npx", "http-server", "-p", "8080"
    ]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        out, err = proc.communicate(timeout=timeout)
        return {"out": out.decode("utf-8"), "err": err.decode("utf-8")}
    except subprocess.TimeoutExpired:
        proc.kill()
        return {"error": "timeout"}
