<template>
    <div class="timeline">
        <highcharts :options="chartOptions"></highcharts>
    </div>
</template>

<script lang="ts">
import { SessionTimeline } from "../store/modules/session";

import { Component, Prop, Vue } from "vue-property-decorator";

@Component
export default class Timeline extends Vue {
    @Prop({ default: { id: "foo", component: "bar", names: [], segments: [] } }) timeline!: SessionTimeline;

    get chartOptions(): any {
        return {
            title: {
                text: this.timeline.id,
            },
            xAxis: {
                categories: this.timeline.labels,
            },
            series: this.timeline.segments.map(segment => { return { name: segment.id, data: segment.samples }; })
        };
    }
}
</script>