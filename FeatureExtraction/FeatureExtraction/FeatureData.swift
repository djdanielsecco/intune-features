//  Copyright © 2015 Venture Media. All rights reserved.

import Foundation
import Upsurge

public class FeatureData {
    public let exampleCount: Int
    public internal(set) var labels: [Int]
    public internal(set) var fileNames: [String]
    public internal(set) var offsets: [Int]
    public internal(set) var data: [String: RealArray]

    init(exampleCount: Int) {
        self.exampleCount = exampleCount

        labels = [Int]()
        labels.reserveCapacity(exampleCount)
        fileNames = [String]()
        fileNames.reserveCapacity(exampleCount)
        offsets = [Int]()
        offsets.reserveCapacity(exampleCount)
        
        data = [String: RealArray]()
    }

    public convenience init(features: [Example: [String: RealArray]]) {
        self.init(exampleCount: features.count)

        for example in features.keys {
            labels.append(example.label)
            fileNames.append(example.filePath)
            offsets.append(example.frameOffset)

            let features = features[example]!
            for (name, featureData) in features {
                var allFeatureData: RealArray
                if let data = data[name] {
                    allFeatureData = data
                } else {
                    allFeatureData = RealArray(capacity: featureData.count * exampleCount)
                    data.updateValue(allFeatureData, forKey: name)
                }
                allFeatureData.appendContentsOf(featureData)
            }
        }
    }
}