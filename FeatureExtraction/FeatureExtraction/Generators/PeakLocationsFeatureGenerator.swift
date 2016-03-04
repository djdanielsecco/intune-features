//  Copyright © 2015 Venture Media. All rights reserved.

import Foundation
import Upsurge

public class PeakLocationsFeatureGenerator: BandsFeatureGenerator {
    public var peakLocations: ValueArray<Double>

    public override var data: ValueArray<Double> {
        return peakLocations
    }
    
    public override init(configuration: Configuration) {
        peakLocations = ValueArray<Double>(count: configuration.bandCount)
        super.init(configuration: configuration)
    }

    public func update(peaks: [Point]) {
        let bandCount = configuration.bandCount
        
        var peaksByBand = [Int: Point]()
        for peak in peaks {
            let note = freqToNote(peak.x)
            let band = configuration.bandForNote(note)
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

        for band in 0..<bandCount {
            let note = configuration.noteForBand(band)
            if let peak = peaksByBand[band] {
                let peakN = freqToNote(peak.x)
                peakLocations[band] = 1.0 - abs(note - peakN)
            } else {
                peakLocations[band] = 0.0
            }
        }
    }
}
