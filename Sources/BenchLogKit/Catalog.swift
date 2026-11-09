import Foundation
import GRDB

/// One place in the catalog: a brand, a model of a brand, or a revision of a model.
public struct CatalogPath: Hashable, Sendable {
    public var category: DeviceCategory
    public var brand: String
    public var model: String?
    public var revision: String?

    public init(category: DeviceCategory, brand: String, model: String? = nil, revision: String? = nil) {
        self.category = category
        self.brand = brand
        self.model = model
        self.revision = revision
    }

    /// The last name in the path: what a rename changes.
    public var name: String { revision ?? model ?? brand }

    /// The same path with its last name replaced.
    public func renamed(_ name: String) -> CatalogPath {
        var path = self
        if revision != nil { path.revision = name } else if model != nil { path.model = name } else { path.brand = name }
        return path
    }
}

/// A node of the catalog outline, with how many devices use it.
public struct CatalogNode: Identifiable, Hashable, Sendable {
    public var path: CatalogPath
    public var deviceCount: Int
    public var children: [CatalogNode]?
    public var id: CatalogPath { path }
    public var name: String { path.name }
}

extension Library {
    /// The catalog as an outline: category → brand → model → revision.
    public func catalogOutline() throws -> [DeviceCategory: [CatalogNode]] {
        try db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT category, brand, model, revision FROM catalog ORDER BY brand COLLATE NOCASE, model COLLATE NOCASE, revision COLLATE NOCASE")
            let counts = try Row.fetchAll(db, sql: """
                SELECT category, lower(brand) AS b, lower(model) AS m, lower(revision) AS r, COUNT(*) AS n
                FROM device WHERE deletedAt IS NULL GROUP BY 1, 2, 3, 4
                """)
            var byKey: [String: Int] = [:]
            for row in counts {
                let c: String = row["category"], b: String = row["b"], m: String = row["m"], r: String = row["r"], n: Int = row["n"]
                for key in ["\(c)|\(b)", "\(c)|\(b)|\(m)", "\(c)|\(b)|\(m)|\(r)"] { byKey[key, default: 0] += n }
            }
            func count(_ parts: String...) -> Int { byKey[parts.map { $0.lowercased() }.joined(separator: "|")] ?? 0 }

            var outline: [DeviceCategory: [CatalogNode]] = [:]
            var grouped: [DeviceCategory: [(brand: String, model: String, revision: String)]] = [:]
            for row in rows {
                guard let category = DeviceCategory(rawValue: row["category"]) else { continue }
                grouped[category, default: []].append((row["brand"], row["model"], row["revision"]))
            }
            for (category, entries) in grouped {
                var brands: [CatalogNode] = []
                for brand in entries.map(\.brand).uniqued() {
                    let ofBrand = entries.filter { $0.brand == brand }
                    var models: [CatalogNode] = []
                    for model in ofBrand.map(\.model).uniqued() {
                        let revisions = ofBrand.filter { $0.model == model && !$0.revision.isEmpty }.map { revision in
                            CatalogNode(path: CatalogPath(category: category, brand: brand, model: model, revision: revision.revision),
                                        deviceCount: count(category.rawValue, brand, model, revision.revision), children: nil)
                        }
                        models.append(CatalogNode(path: CatalogPath(category: category, brand: brand, model: model),
                                                  deviceCount: count(category.rawValue, brand, model),
                                                  children: revisions.isEmpty ? nil : revisions))
                    }
                    brands.append(CatalogNode(path: CatalogPath(category: category, brand: brand),
                                              deviceCount: count(category.rawValue, brand), children: models))
                }
                outline[category] = brands
            }
            return outline
        }
    }

    /// The other names at the same level as the path, for Merge Into.
    public func catalogSiblings(of path: CatalogPath) throws -> [String] {
        let names: [String]
        if let model = path.model, path.revision != nil {
            names = try catalogRevisions(path.category, brand: path.brand, model: model)
        } else if path.model != nil {
            names = try catalogModels(path.category, brand: path.brand)
        } else {
            names = try catalogBrands(path.category)
        }
        return names.filter { $0.caseInsensitiveCompare(path.name) != .orderedSame }
    }

    /// Renames a brand, model, or revision everywhere: in the catalog, on devices, and on
    /// the models parts fit. Renaming to a name that already exists merges the two.
    public func renameCatalog(_ path: CatalogPath, to newName: String, now: Date = .now) throws {
        let newName = newName.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != path.name else { return }
        try db.write { db in
            let (column, filter, arguments) = Self.catalogFilter(path)
            // Catalog rows: move what does not collide, then drop the old rows that did.
            try db.execute(sql: "UPDATE OR IGNORE catalog SET \(column) = ? WHERE \(filter)", arguments: [newName] + arguments)
            // A rename that only changes case still matches the old filter: keep the new spelling.
            try db.execute(sql: "DELETE FROM catalog WHERE \(filter) AND \(column) <> ?", arguments: arguments + [newName])
            try db.execute(sql: "UPDATE device SET \(column) = ?, updatedAt = ? WHERE \(filter)",
                           arguments: [newName, now] + arguments)
            if path.revision == nil {
                try db.execute(sql: "UPDATE OR IGNORE partFit SET \(column) = ? WHERE \(filter)", arguments: [newName] + arguments)
                try db.execute(sql: "DELETE FROM partFit WHERE \(filter) AND \(column) <> ?", arguments: arguments + [newName])
            }
        }
    }

    /// Removes a brand, model, or revision (and what is under it) from the catalog. Devices
    /// keep their names; saving one adds its name back.
    public func deleteFromCatalog(_ path: CatalogPath) throws {
        try db.write { db in
            let (_, filter, arguments) = Self.catalogFilter(path)
            try db.execute(sql: "DELETE FROM catalog WHERE \(filter)", arguments: arguments)
        }
    }

    /// The column a rename changes, and the WHERE clause that matches the path in the
    /// catalog, device, and partFit tables (they share these column names).
    private static func catalogFilter(_ path: CatalogPath) -> (String, String, StatementArguments) {
        var filter = "category = ? AND brand = ? COLLATE NOCASE"
        var arguments: StatementArguments = [path.category.rawValue, path.brand]
        var column = "brand"
        if let model = path.model {
            filter += " AND model = ? COLLATE NOCASE"
            _ = arguments.append(contentsOf: [model])
            column = "model"
        }
        if let revision = path.revision {
            filter += " AND revision = ? COLLATE NOCASE"
            _ = arguments.append(contentsOf: [revision])
            column = "revision"
        }
        return (column, filter, arguments)
    }
}

private extension Array where Element == String {
    /// The names in order, without repeats.
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
