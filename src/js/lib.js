const functions = {
  get_platform_name: () => {
    console.log("Javascript WASM");
  },
  update_fps_counter: (fps) => {
    document.getElementById("fps_counter").innerText = "FPS: " + fps;
  },
};
