struct LocationKey: Hashable {
    let segment: Int
    let procedure: Int?
    let lexLevel: Int?
    let addr: Int?

    init(_ location: Location) {
        self.segment = location.segment
        self.procedure = location.procedure
        self.lexLevel = location.lexLevel
        self.addr = location.addr
    }
}

struct CanonicalLocationMap {
    private let locationsByKey: [LocationKey: Location]

    init(_ locations: Set<Location>) {
        self.locationsByKey = Dictionary(uniqueKeysWithValues: locations.map {
            (LocationKey($0), $0)
        })
    }

    func canonicalLocation(matching location: Location?) -> Location? {
        guard let location else { return nil }
        return locationsByKey[LocationKey(location)] ?? location
    }
}
