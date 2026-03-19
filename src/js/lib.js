const canvas = document.getElementById("canvas");
const resizeObserver = new ResizeObserver((entries) => {
  for (const entry of entries) {
    const { width, height } = entry.contentRect;
    canvas.width = Math.floor(width);
    canvas.height = Math.floor(height);
  }
});
resizeObserver.observe(canvas, { box: "content-box" });

const functions = {
  get_platform_name: () => {
    console.log("Javascript WASM");
  },
  update_fps_counter: (fps) => {
    document.getElementById("fps_counter").innerText = "FPS: " + fps;
  },
};
