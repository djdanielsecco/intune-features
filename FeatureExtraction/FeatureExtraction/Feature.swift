//  Copyright © 2016 Venture Media. All rights reserved.

import Upsurge

public struct Feature {
    public var rms: Real
    public var spectrum: RealArray
    public var spectralFlux: RealArray
    public var peakHeights: RealArray
    public var peakLocations: RealArray

    public init() {
        rms = 0
        spectrum = RealArray()
        spectralFlux = RealArray()
        peakHeights = RealArray()
        peakLocations = RealArray()
    }

    public init(rms: Real, spectrum: RealArray, spectralFlux: RealArray, peakHeights: RealArray, peakLocations: RealArray) {
        self.rms = rms
        self.spectrum = spectrum
        self.spectralFlux = spectralFlux
        self.peakHeights = peakHeights
        self.peakLocations = peakLocations
    }
}
