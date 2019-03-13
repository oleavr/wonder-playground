<template>
    <div class="session">
        <ul class="timelines" v-if="session.socket">
            <li class="timeline" v-for="(timeline, id) in timelines" :key="id">
                <Timeline :timeline="timeline"></Timeline>
            </li>
        </ul>
        <button v-on:click="turnLeft">Turn left</button>
        <h3 v-if="session.error">Oops: {{ session.error.message }}</h3>
    </div>
</template>

<script lang="ts">
import { SessionState, SessionTimeline } from "../store/modules/session";
import Timeline from "./Timeline.vue";

import { Component, Vue } from "vue-property-decorator";
import { State, Action, Getter } from "vuex-class";

const namespace: string = "session";

@Component({
    components: {
        Timeline,
    },
})
export default class Session extends Vue {
    @State("session") session!: SessionState;
    @Action("connect", { namespace }) connect!: () => Promise<void>;
    @Action("turnLeft", { namespace }) turnLeft!: () => Promise<void>;
    @Getter("timelines", { namespace }) timelines!: SessionTimeline[];

    mounted(): void {
        this.connect();
    }
}
</script>

<style scoped>
ul.timelines {
    display: grid;
    grid-template-columns: 1fr 1fr;
    grid-row-gap: 10px;
    grid-column-gap: 10px;
    padding: 10px;
    margin: 0;
    list-style-type: none;
}

@media (min-width: 1280px) {
    ul.timelines {
        grid-template-columns: 1fr 1fr 1fr;
    }
}
</style>