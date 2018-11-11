import App from "./App.vue";
import store from "./store";

import Vue from "vue";

Vue.config.productionTip = false;

new Vue({
    el: "#app",
    store,
    render: h => h(App)
});