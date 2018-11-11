<template>
    <div id="app">
        <img class="logo" alt="Frida logo" src="./assets/logo.png">
        <Session />
    </div>
</template>

<script lang="ts">
import Session from "./components/Session.vue";

import HighchartsVue from "highcharts-vue";
import { Component, Vue } from "vue-property-decorator";

Vue.use(HighchartsVue);

@Component({
    components: {
        Session,
    },
})
export default class App extends Vue {}
</script>

<style>
body {
    margin: 0;
    background-color: #f1f1f1;
}

#app {
    font-family: 'Avenir', Helvetica, Arial, sans-serif;
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
    text-align: center;
    color: #2c3e50;
}

.logo {
    width: 64px;
    height: 64px;
    margin-top: 10px;
}
</style>