//
//  SonauraTests.swift
//  SonauraTests
//
//  Created by Mo Alraiyes on 10/2/25.
//

import Testing
import Foundation
@testable import Sonaura

/// Tests over the numbers the whole app rests on.
///
/// Sonaura reports dB HL bands and ISO 7029 percentiles, so its output is only
/// as good as this arithmetic — and until now none of it was covered. Two bugs
/// that made the app stop measuring anything at all would each have been caught
/// by a single assertion in here:
///
/// 1. `AirPodsCalibration` floored low amplitudes to keep them audible in
///    16-bit, which presented the 15 dB HL tone at roughly 25 dB HL and
///    collapsed a 10 dB gap between rungs to about 2 dB. Caught by
///    `levelsStayTenDecibelsApart`.
/// 2. `TonePlayer.cacheKey` truncated amplitude with `Int(amplitude * 1000)`,
///    so every level in the ladder shared one key and replayed the same WAV.
///    Caught by `cacheKeysDifferPerLevel`.
///
/// Anything that changes the calibration chain or the tone cache should fail
/// here first.
struct CalibrationTests {

    private let screeningLevels: [Double] = [15, 25, 40, 55]
    private let frequencies = [250, 500, 1000, 2000, 4000, 8000]
    private let model = AirPodsCalibration.ModelType.airPodsPro

    /// Distinct target levels must produce distinct amplitudes, increasing with level.
    ///
    /// The old minimum-amplitude clamp made the two lowest rungs nearly equal,
    /// which is indistinguishable from having no ladder at all.
    @Test func distinctLevelsProduceDistinctAmplitudes() {
        for frequency in frequencies {
            let amplitudes = screeningLevels.map {
                AirPodsCalibration.amplitudeForTargetHL(targetHL: $0, frequency: frequency, model: model)
            }
            #expect(Set(amplitudes).count == amplitudes.count,
                    "\(frequency) Hz: levels collapsed onto shared amplitudes \(amplitudes)")
            for index in 1..<amplitudes.count {
                #expect(amplitudes[index] > amplitudes[index - 1],
                        "\(frequency) Hz: amplitude did not increase from level \(index - 1) to \(index)")
            }
        }
    }

    /// A 10 dB HL difference must be a 10 dB amplitude difference, to within rounding.
    ///
    /// This is the assertion the clamp would have failed loudest: at 2 kHz it
    /// turned the 15→25 dB HL step into roughly 2 dB.
    @Test func levelsStayTenDecibelsApart() {
        for frequency in frequencies {
            let quiet = AirPodsCalibration.amplitudeForTargetHL(targetHL: 15, frequency: frequency, model: model)
            let loud = AirPodsCalibration.amplitudeForTargetHL(targetHL: 25, frequency: frequency, model: model)
            let separationDB = 20 * log10(loud / quiet)
            #expect(abs(separationDB - 10.0) < 0.01,
                    "\(frequency) Hz: 15→25 dB HL separation was \(separationDB) dB, expected 10")
        }
    }

    /// Every level in the ladder must be reachable as a player volume ≤ 1.0.
    ///
    /// `TonePlayer` refuses anything above the carrier rather than presenting
    /// it at the wrong loudness, so an unreachable level is a silently skipped
    /// measurement. It should never happen for the standard ladder.
    @Test func everyScreeningLevelIsReachable() {
        for frequency in frequencies {
            for level in screeningLevels {
                let amplitude = AirPodsCalibration.amplitudeForTargetHL(
                    targetHL: level, frequency: frequency, model: model
                )
                let playerVolume = Float(amplitude) / TonePlayer.carrierAmplitude
                #expect(playerVolume > 0 && playerVolume <= 1.0,
                        "\(frequency) Hz @ \(level) dB HL needs player volume \(playerVolume)")
            }
        }
    }

    /// Amplitude must rise with target level for every model, not just the default.
    @Test func amplitudeIsMonotonicAcrossModels() {
        for model in AirPodsCalibration.ModelType.allCases {
            let quiet = AirPodsCalibration.amplitudeForTargetHL(targetHL: 15, frequency: 1000, model: model)
            let loud = AirPodsCalibration.amplitudeForTargetHL(targetHL: 55, frequency: 1000, model: model)
            #expect(loud > quiet, "\(model.rawValue): 55 dB HL was not louder than 15 dB HL")
        }
    }

    /// Documents *why* the level cannot be baked into the samples.
    ///
    /// Not a regression guard so much as a standing explanation: if someone
    /// removes the carrier-amplitude indirection in `TonePlayer`, this is the
    /// number that explains why the tone went silent and why the temptation to
    /// re-add a minimum-amplitude clamp must be resisted.
    @Test func lowLevelsWouldVanishInSixteenBitSamples() {
        let amplitude = AirPodsCalibration.amplitudeForTargetHL(
            targetHL: 15, frequency: 1000, model: .airPodsPro
        )
        let sixteenBitSample = Int(amplitude * 32767)
        #expect(sixteenBitSample == 0,
                "Expected 15 dB HL to quantise to silence in 16-bit; got \(sixteenBitSample)")

        // The same amplitude expressed as player volume is comfortably
        // representable, which is the whole reason the attenuation lives there.
        let playerVolume = Float(amplitude) / TonePlayer.carrierAmplitude
        #expect(playerVolume > 0)
    }
}

/// Tests over the tone cache key.
///
/// The key is load-bearing in a way that is easy to miss: a collision does not
/// throw or log, it silently replays the previous level's audio, so the test
/// still "runs" and still produces an audiogram — just a meaningless one.
struct ToneCacheTests {

    /// Two different levels at the same frequency and ear must never share a key.
    ///
    /// This is the direct regression guard for `Int(amplitude * 1000)`, which
    /// truncated every screening amplitude to `0`.
    @Test func cacheKeysDifferPerLevel() {
        let player = TonePlayer()
        let amplitudes: [Float] = [0.0000251, 0.0000794, 0.000501, 0.00316]
        let keys = amplitudes.map {
            player.debugCacheKey(frequency: 2000, duration: 0.5, amplitude: $0, ear: .left)
        }
        #expect(Set(keys).count == keys.count,
                "Screening amplitudes collided onto shared cache keys: \(keys)")
    }

    /// Ear and frequency must still separate keys.
    @Test func cacheKeysSeparateEarAndFrequency() {
        let player = TonePlayer()
        let left = player.debugCacheKey(frequency: 1000, duration: 0.5, amplitude: 0.5, ear: .left)
        let right = player.debugCacheKey(frequency: 1000, duration: 0.5, amplitude: 0.5, ear: .right)
        let other = player.debugCacheKey(frequency: 2000, duration: 0.5, amplitude: 0.5, ear: .left)
        #expect(left != right)
        #expect(left != other)
    }
}
