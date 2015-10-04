//  Copyright © 2015 Venture Media. All rights reserved.

import Foundation
import Surge

struct Feature {
    let peakCount: Int
    let noteCount: Int
    
    var label: Int = -1
    var peaks: [Point] {
        willSet {
            precondition(newValue.count == peakCount)
        }
    }
    var bands: [Double] {
        willSet {
            precondition(newValue.count == noteCount)
        }
    }
    
    init(peakCount: Int, noteCount: Int) {
        self.peakCount = peakCount
        self.noteCount = noteCount
        
        peaks = [Point](count: peakCount, repeatedValue: Point())
        bands = [Double](count: noteCount, repeatedValue: 0.0)
    }

    static func dataSize(peakCount: Int, noteCount: Int) -> Int {
        return 2 * peakCount + noteCount
    }

    func data() -> [Double] {
        var data = [Double]()
        for point in peaks {
            data.appendContentsOf([point.x, point.y])
        }
        data.appendContentsOf(bands)
        return data
    }
}