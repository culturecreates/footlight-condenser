// Entry point for the build script in your package.json
import ujs from "@rails/ujs";
ujs.start();
// import "@hotwired/turbo-rails"; // Disabled Turbo for the entire website
import consumer from "./channels/cable";