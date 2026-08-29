import AVFoundation
import MediaPlayer
import SwiftUI

/// Forces the device's system volume to maximum while `isActive`, and
/// fights back immediately if the user tries to lower it (via the
/// physical buttons or Control Center) — otherwise turning the volume down
/// is a trivial way to defeat the whole point of a mission-gated alarm.
///
/// `AVAudioSession.Category.playback` (what `LocalAlarmAudioPlayer` uses)
/// is real media-style audio and fully volume-slider-adjustable, unlike
/// AlarmKit's own native alert sound — there's no public API for a
/// third-party app to play audio that ignores the volume slider outright
/// (that's reserved for Apple-granted "critical alerts"), so this uses the
/// standard (if unofficial) `MPVolumeView`-slider technique instead: it
/// doesn't prevent the volume from being *changed*, it just corrects it
/// back up within a fraction of a second every time it's lowered.
struct VolumeForcer: UIViewRepresentable {
    var isActive: Bool

    func makeUIView(context: Context) -> MPVolumeView {
        // MPVolumeView must be part of a real window for its embedded
        // slider to actually affect system volume, not just floating
        // unattached -- SwiftUI's UIViewRepresentable hosting handles that
        // for us since this view is part of the real view hierarchy.
        let view = MPVolumeView(frame: .zero)
        view.alpha = 0.001 // effectively invisible, but "hidden = true" can stop the slider from working
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        context.coordinator.setActive(isActive, volumeView: uiView)
    }

    static func dismantleUIView(_ uiView: MPVolumeView, coordinator: Coordinator) {
        coordinator.setActive(false, volumeView: uiView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        private var observer: NSKeyValueObservation?
        private var isForcing = false

        func setActive(_ active: Bool, volumeView: MPVolumeView) {
            guard active != isForcing else { return }
            isForcing = active

            if active {
                forceMaxVolume(via: volumeView)
                let session = AVAudioSession.sharedInstance()
                observer = session.observe(\.outputVolume, options: [.new]) { [weak self, weak volumeView] _, change in
                    guard let self, let volumeView, self.isForcing else { return }
                    guard let newValue = change.newValue, newValue < 1.0 else { return }
                    Task { @MainActor in
                        self.forceMaxVolume(via: volumeView)
                    }
                }
            } else {
                observer?.invalidate()
                observer = nil
            }
        }

        private func forceMaxVolume(via volumeView: MPVolumeView) {
            guard let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider else { return }
            slider.value = 1.0
        }
    }
}
