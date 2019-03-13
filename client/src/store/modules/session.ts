import { RootState } from "../types";

import { ActionTree, MutationTree, Module, ActionContext } from "vuex";
import WebSocketAsPromised from "websocket-as-promised";

const namespaced: boolean = true;

export interface SessionState {
    timelines: SessionTimeline[];

    socket: WebSocketAsPromised | null;
    error: Error | null;
}

export interface SessionTimeline {
    id: string;
    component: string;
    labels: string[];
    segments: SessionTimelineSegment[];
}

export interface SessionTimelineSegment {
    id: string;
    samples: number[];
}

export const state: SessionState = {
    timelines: [],

    socket: null,
    error: null,
};

import { GetterTree } from "vuex";

export const getters: GetterTree<SessionState, RootState> = {
    timelines(state): SessionTimeline[] {
        return state.timelines;
    }
};

export const actions: ActionTree<SessionState, RootState> = {
    async connect({ commit }): Promise<void> {
        const wsp = new WebSocketAsPromised("ws://127.0.0.1:1337/session", {
            packMessage: data => JSON.stringify(data),
            unpackMessage: message => JSON.parse(message as string)
        });

        let connecting = true;

        const onClose = details => {
            if (connecting)
                return;
            commit("socketError", new Error("Lost connection to server"));
        };
        wsp.onClose.addListener(onClose as any);

        const onUnpackedMessage = (message: SocketMessage) => {
            commit("socketMessage", message);
        };
        wsp.onUnpackedMessage.addListener(onUnpackedMessage as any);

        try {
            await wsp.open();
            connecting = false;
            commit("socketConnected", wsp);
        } catch (e) {
            commit("socketError", new Error("Unable to connect to server"));
        }
    },

    async turnLeft(store: ActionContext<SessionState, RootState>): Promise<void> {
        const {socket} = store.state;
        if (socket === null) {
            return;
        }

        const degrees = 120;
        const timeMs = 1000;

        let rawDegrees = degrees * 628 / 360;
        let byte7 = 0x00;
        if (rawDegrees < 0) {
            rawDegrees += 0x400;
            byte7 = 0xc0;
        }

        const byte4 = timeMs & 0xff;
        const byte5 = timeMs >>> 8;

        const byte3 = rawDegrees & 0xff;
        const byte6 = (rawDegrees >>> 10) << 6;

        const packet = new Uint8Array([
            0x23, 0x00, 0x00, byte3, byte4, byte5, byte6, byte7
        ]);
        socket.send(packet);
    }
}

        /*
        const packet = new Uint8Array([
            0x03, 0xff, 0x00, 0x00, 0x0b, 0xff, 0x00, 0x00,
            0x0c, 0xff, 0x00, 0x00, 0x30, 0xff, 0x00, 0x00,
        ]);
        */


export const mutations: MutationTree<SessionState> = {
    socketConnected(state, socket: WebSocketAsPromised) {
        state.timelines = [];

        state.socket = socket;
        state.error = null;
    },
    socketError(state, error: Error) {
        state.socket = null;
        state.error = error;
    },
    socketMessage(state, message: SocketMessage) {
        const [ type, payload ] = message;

        if (type === "sync") {
            const sync = payload as SyncPayload;
            state.timelines = sync.timelines;
            return;
        }

        if (type === "sample-added" || type === "sample-updated") {
            const [ timelineId, segmentId, label, sample, index ] = payload as SampleNotificationPayload;

            const timeline = state.timelines.find(timeline => timeline.id === timelineId);
            if (timeline === undefined) {
                throw new Error("Invalid timeline ID");
            }

            const segment = timeline.segments.find(segment => segment.id === segmentId);
            if (segment === undefined) {
                throw new Error("Invalid segment ID");
            }

            if (type === "sample-added") {
                if (timeline.labels.length === index) {
                    timeline.labels.push(label);
                }

                segment.samples.push(sample);
            } else {
                const newSamples = segment.samples.slice();
                newSamples[index] = sample;
                segment.samples = newSamples;
            }

            return;
        }

        console.log("Got unknown message:", message);
    }
};

type SocketMessage = [ "sync", SyncPayload ]
    | [ "sample-added", SampleNotificationPayload ]
    | [ "sample-updated", SampleNotificationPayload ];

interface SyncPayload {
    timelines: SessionTimeline[];
}

type SampleNotificationPayload = [ string, string, string, number, number ];

export const session: Module<SessionState, RootState> = {
    namespaced,
    state,
    getters,
    actions,
    mutations
};