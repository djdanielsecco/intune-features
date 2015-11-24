//  Copyright © 2015 Venture Media. All rights reserved.

import HDF5Kit
import Upsurge

public class FeatureDatabase {
    let chunkSize = 1024
    let filePath: String
    let file: File

    let doubleDatasetSpecs = [
        (name: "peak_locations", size: FeatureBuilder.bandNotes.count),
        (name: "peak_heights", size: FeatureBuilder.bandNotes.count),
        (name: "spectrum", size: FeatureBuilder.bandNotes.count),
        (name: "spectrum_flux", size: FeatureBuilder.bandNotes.count)
    ]
    let intDatasetSpecs = [
        (name: "label", size: FeatureBuilder.bandNotes.count),
        (name: "offset", size: 1),
    ]
    let stringDatasetSpecs = [
        (name: "fileName"),
        (name: "folder"),
    ]

    struct DoubleTable {
        var name: String
        var size: Int
        var dataset: Dataset
        var data: RealArray
    }

    struct IntTable {
        var name: String
        var size: Int
        var dataset: Dataset
        var data: [Int]
    }

    struct StringTable {
        var name: String
        var dataset: Dataset
        var data: [String]
    }

    var doubleTables = [DoubleTable]()
    var intTables = [IntTable]()
    var stringTables = [StringTable]()

    public internal(set) var folders = [String]()
    public internal(set) var exampleCount = 0

    var pendingFeatures = [FeatureData]()

    public init(filePath: String, overwrite: Bool) {
        self.filePath = filePath

        if overwrite {
            file = File.create(filePath, mode: .Truncate)!
            create()
        } else if let file = File.open(filePath, mode: .ReadWrite) {
            self.file = file
            load()
        } else {
            file = File.create(filePath, mode: .Exclusive)!
            create()
        }
    }

    func create() {
        for (name, size) in doubleDatasetSpecs {
            let space = Dataspace(dims: [0, size], maxDims: [-1, size])
            let dataset = file.createDataset(name, datatype: Datatype.createDouble(), dataspace: space, chunkDimensions: [chunkSize, size])
            let table = DoubleTable(name: name, size: size, dataset: dataset, data: RealArray(count: chunkSize * size))
            doubleTables.append(table)
        }
        for (name, size) in intDatasetSpecs {
            let space = Dataspace(dims: [0, size], maxDims: [-1, size])
            let dataset = file.createDataset(name, datatype: Datatype.createInt(), dataspace: space, chunkDimensions: [chunkSize, size])
            let table = IntTable(name: name, size: size, dataset: dataset, data: [Int](count: chunkSize * size, repeatedValue: 0))
            intTables.append(table)
        }
        for name in stringDatasetSpecs {
            let space = Dataspace(dims: [0], maxDims: [-1])
            let dataset = file.createDataset(name, datatype: Datatype.createString(), dataspace: space, chunkDimensions: [chunkSize])
            let table = StringTable(name: name, dataset: dataset, data: [String](count: chunkSize, repeatedValue: ""))
            stringTables.append(table)
        }
    }

    func load() {
        for (name, size) in doubleDatasetSpecs {
            guard let dataset = file.openDataset(name) else {
                preconditionFailure("Existing file doesn't have a \(name) dataset")
            }

            guard let nativeType = dataset.type.nativeType else {
                preconditionFailure("Existing dataset '\(name)' is not of a native data type")
            }
            precondition(nativeType == .Double, "Existing dataset '\(name)' is of the wrong type")

            let dims = dataset.space.dims
            precondition(dims.count == 2 && dims[1] == size, "Existing dataset '\(name)' is of the wrong size")

            let table = DoubleTable(name: name, size: size, dataset: dataset, data: RealArray(count: size * chunkSize))
            doubleTables.append(table)
        }
        for (name, size) in intDatasetSpecs {
            guard let dataset = file.openDataset(name) else {
                preconditionFailure("Existing file doesn't have a \(name) dataset")
            }

            guard let nativeType = dataset.type.nativeType else {
                preconditionFailure("Existing dataset '\(name)' is not of a native data type")
            }
            precondition(nativeType == .Int, "Existing dataset '\(name)' is of the wrong type")

            let dims = dataset.space.dims
            precondition(dims.count == 2 && dims[1] == size, "Existing dataset '\(name)' is of the wrong size")

            let table = IntTable(name: name, size: size, dataset: dataset, data: [Int](count: size * chunkSize, repeatedValue: 0))
            intTables.append(table)
        }
        for name in stringDatasetSpecs {
            guard let dataset = file.openDataset(name) else {
                preconditionFailure("Existing file doesn't have a \(name) dataset")
            }

            let dims = dataset.space.dims
            precondition(dims.count == 1, "Existing dataset '\(name)' is of the wrong size")

            let table = StringTable(name: name, dataset: dataset, data: [String](count: chunkSize, repeatedValue: ""))
            stringTables.append(table)
        }

        let foldersTable = stringTables.filter({ $0.name == "folder" }).first!
        folders = foldersTable.dataset.readString()!
    }

    public func appendFeatures(features: [FeatureData], folder: String?) {
        var offset = 0

        if pendingFeatures.count > 0 {
            let missing = chunkSize - pendingFeatures.count
            offset = min(missing, features.count)
            pendingFeatures += features[0..<offset]
            if pendingFeatures.count < chunkSize {
                // Not enough data for a full chunk
                return
            }
        }

        if pendingFeatures.count == chunkSize {
            appendChunk(ArraySlice(pendingFeatures))
            pendingFeatures.removeAll(keepCapacity: true)
        }

        while features.count - offset >= chunkSize {
            appendChunk(features[offset..<offset + chunkSize])
            offset += chunkSize
        }

        pendingFeatures += features[offset..<features.count]

        if let folder = folder {
            let foldersTable = stringTables.filter({ $0.name == "folder" }).first!
            appendFolder(folder, forTable: foldersTable)
        }

        file.flush()
    }

    func appendChunk(features: ArraySlice<FeatureData>) {
        assert(features.count == chunkSize)

        for table in doubleTables {
            appendDoubleChunk(features, forTable: table)
        }

        let labelsTable = intTables.filter({ $0.name == "label" }).first!
        appendLabelsChunk(features, forTable: labelsTable)

        let offsetsTable = intTables.filter({ $0.name == "offset" }).first!
        appendOffsetsChunk(features, forTable: offsetsTable)

        let fileNamesTable = stringTables.filter({ $0.name == "fileName" }).first!
        appendFileNamesChunk(features, forTable: fileNamesTable)

        exampleCount += features.count
    }

    func appendDoubleChunk(features: ArraySlice<FeatureData>, forTable table: DoubleTable) {
        let currentSize = table.dataset.extent[0]
        table.dataset.extent[0] += chunkSize

        let filespace = table.dataset.space
        filespace.select(start: [currentSize, 0], stride: nil, count: [chunkSize, table.size], block: nil)

        assert(table.data.capacity == chunkSize * table.size)
        table.data.count = 0
        let memspace = Dataspace(dims: [chunkSize, table.size])

        for featureData in features {
            guard let data = featureData.features[table.name] else {
                fatalError("Feature is missing dataset \(table.name)")
            }
            table.data.appendContentsOf(data)
        }

        if !table.dataset.writeDouble(table.data.pointer, memSpace: memspace, fileSpace: filespace) {
            fatalError("Failed to write features to database")
        }
    }

    func appendLabelsChunk(features: ArraySlice<FeatureData>, var forTable table: IntTable) {
        let currentSize = table.dataset.extent[0]
        table.dataset.extent[0] += chunkSize

        let filespace = table.dataset.space
        filespace.select(start: [currentSize, 0], stride: nil, count: [chunkSize, table.size], block: nil)

        table.data.removeAll(keepCapacity: true)
        let memspace = Dataspace(dims: [chunkSize, table.size])

        for feature in features {
            table.data.appendContentsOf(feature.example.label)
        }
        if !table.dataset.writeInt(table.data.pointer, memSpace: memspace, fileSpace: filespace) {
            fatalError("Failed to write features to database")
        }
    }

    func appendOffsetsChunk(features: ArraySlice<FeatureData>, var forTable table: IntTable) {
        let currentSize = table.dataset.extent[0]
        table.dataset.extent[0] += chunkSize

        let filespace = table.dataset.space
        filespace.select(start: [currentSize, 0], stride: nil, count: [chunkSize, table.size], block: nil)

        table.data.removeAll(keepCapacity: true)
        let memspace = Dataspace(dims: [chunkSize, table.size])

        for feature in features {
            table.data.append(feature.example.frameOffset)
        }
        if !table.dataset.writeInt(table.data.pointer, memSpace: memspace, fileSpace: filespace) {
            fatalError("Failed to write features to database")
        }
    }

    func appendFileNamesChunk(features: ArraySlice<FeatureData>, var forTable table: StringTable) {
        let currentSize = table.dataset.extent[0]
        table.dataset.extent[0] += chunkSize

        let filespace = table.dataset.space
        filespace.select(start: [currentSize], stride: nil, count: [chunkSize], block: nil)

        table.data.removeAll(keepCapacity: true)
        let memspace = Dataspace(dims: [chunkSize])

        for feature in features {
            table.data.append(feature.example.filePath)
        }
        if !table.dataset.writeString(table.data, memSpace: memspace, fileSpace: filespace) {
            fatalError("Failed to write features to database")
        }
    }

    func appendFolder(folder: String, var forTable table: StringTable) {
        folders.append(folder)

        let currentSize = table.dataset.extent[0]
        table.dataset.extent[0] += 1

        let filespace = table.dataset.space
        filespace.select(start: [currentSize], stride: nil, count: [1], block: nil)

        table.data.removeAll(keepCapacity: true)
        let memspace = Dataspace(dims: [1])

        table.data.append(folder)
        if !table.dataset.writeString(table.data, memSpace: memspace, fileSpace: filespace) {
            fatalError("Failed to write features to database")
        }
    }
}