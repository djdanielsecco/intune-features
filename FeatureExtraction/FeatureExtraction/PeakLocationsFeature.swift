//  Copyright © 2015 Venture Media. All rights reserved.

import Foundation
import Upsurge

public class PeakLocationsFeature : BandsFeature {
    public typealias Peak = Upsurge.Point<Double>

    public var peakLocations = RealArray()

    public override var data: RealArray {
        return peakLocations
    }
    
    public override init() {}

    public func update(peaks: [Peak]) {
        let bandCount = Int(Double(SpectrumFeature.notes.count) / SpectrumFeature.bandSize)
        
        var peaksByBand = [Int: Peak]()
        for peak in peaks {
            let note = freqToNote(peak.x)
            let band = bandForNote(note)
            guard band >= 0 && band < bandCount else {
                continue
            }

            if let existingPeak = peaksByBand[band] {
                if existingPeak.y < peak.y {
                    peaksByBand[band] = peak
                }
            } else {
                peaksByBand[band] = peak
            }
        }

        peakLocations = RealArray(count: bandCount)

        for band in 0..<bandCount {
            let note = noteForBand(band)
            if let peak = peaksByBand[band] {
                let peakN = freqToNote(peak.x)
                peakLocations[band] = 1.0 - abs(note - peakN)
            } else {
                peakLocations[band] = 0.0
            }
        }
    }
}
