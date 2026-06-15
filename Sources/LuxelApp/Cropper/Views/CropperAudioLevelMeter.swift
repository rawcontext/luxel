import SwiftUI

struct CropperAudioLevelMeter: View {
    @Bindable var model: LuxelAudioLevelModel

    var body: some View {
        AudioLevelMeterView(sample: model.sample)
    }
}
