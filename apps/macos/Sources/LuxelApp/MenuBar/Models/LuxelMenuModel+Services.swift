import LuxelCore

extension LuxelMenuModel {
    static func makeRecordingLifecycleServices(
        _ dependencies: RecordingLifecycleDependencies
    ) -> RecordingLifecycleServices {
        let outputFinalizer = LuxelCompositionRoot.recordingOutputFinalizer()
        let terminationProtection = ProcessInfoRecordingProtection()
        let publishAudioLevel: @Sendable (AudioLevelSample) -> Void = {
            dependencies.broadcaster.publish($0)
        }
        let video = RecordingLifecycleService(
            recorder: dependencies.recorder
                ?? LuxelCompositionRoot.captureRecorder(
                    exclusionRegistry: dependencies.exclusionRegistry,
                    audioLevelHandler: publishAudioLevel
                ),
            history: dependencies.history,
            userNotifier: UserNotificationsNotifier(),
            outputFinalizer: outputFinalizer,
            replayBufferService: dependencies.replayBufferService,
            terminationProtection: terminationProtection
        )
        let audio = AudioRecordingLifecycleService(
            recorder: dependencies.audioRecorder
                ?? LuxelCompositionRoot.audioRecorder(audioLevelHandler: publishAudioLevel),
            history: dependencies.history,
            outputFinalizer: outputFinalizer,
            terminationProtection: terminationProtection
        )
        return RecordingLifecycleServices(video: video, audio: audio)
    }
}
