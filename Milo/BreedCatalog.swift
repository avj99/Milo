import Foundation

/// A pre-built, in-app reference of common dog breeds with their **typical
/// healthy adult weight range** and size class.
///
/// Sourcing & method: these are factual weight ranges compiled from public
/// breed standards (AKC/FCI/The Kennel Club) and veterinary ideal-weight
/// references (Association for Pet Obesity Prevention). Raw factual ranges are
/// not copyrightable, so this table is owned outright and safe for commercial
/// use. Ranges are deliberately presented as *typical ranges*, never a single
/// "correct" number — an individual dog's ideal weight is confirmed with body
/// condition score and a vet, not breed alone.
enum DogSize: String, Codable, CaseIterable {
    case toy, small, medium, large, giant

    /// Age (months) by which the breed is typically skeletally mature. Bigger
    /// breeds grow for longer, so they stay on the puppy energy curve longer.
    var maturityMonths: Int {
        switch self {
        case .toy, .small: return 12
        case .medium:      return 15
        case .large:       return 18
        case .giant:       return 24
        }
    }

    /// Fallback ideal-weight range (kg) when the breed is unknown/mixed.
    var fallbackRangeKg: (lo: Double, hi: Double) {
        switch self {
        case .toy:    return (2, 5)
        case .small:  return (5, 12)
        case .medium: return (12, 25)
        case .large:  return (25, 45)
        case .giant:  return (45, 80)
        }
    }

    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

struct BreedInfo: Identifiable, Hashable {
    let name: String
    let size: DogSize
    let idealLoKg: Double
    let idealHiKg: Double

    var id: String { name }
    var midKg: Double { (idealLoKg + idealHiKg) / 2 }

    /// e.g. "Large · 25–36 kg"
    var summary: String {
        "\(size.label) · \(BreedInfo.fmt(idealLoKg))–\(BreedInfo.fmt(idealHiKg)) kg"
    }

    static func fmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }
}

enum BreedCatalog {

    /// Typical healthy adult weight ranges (kg), union of both sexes.
    static let all: [BreedInfo] = [
        b("Labrador Retriever", .large, 25, 36),
        b("Golden Retriever", .large, 25, 34),
        b("German Shepherd", .large, 22, 40),
        b("French Bulldog", .small, 8, 14),
        b("Bulldog (English)", .medium, 18, 25),
        b("Poodle (Standard)", .large, 18, 32),
        b("Poodle (Miniature)", .small, 5, 9),
        b("Poodle (Toy)", .toy, 2, 4),
        b("Beagle", .small, 9, 12),
        b("Rottweiler", .giant, 36, 61),
        b("German Shorthaired Pointer", .large, 20, 32),
        b("Dachshund (Standard)", .small, 7, 15),
        b("Dachshund (Miniature)", .toy, 4, 5),
        b("Pembroke Welsh Corgi", .small, 10, 14),
        b("Australian Shepherd", .medium, 16, 32),
        b("Yorkshire Terrier", .toy, 2, 3.2),
        b("Boxer", .large, 25, 32),
        b("Great Dane", .giant, 45, 90),
        b("Siberian Husky", .medium, 16, 27),
        b("Cavalier King Charles Spaniel", .small, 5.9, 8.2),
        b("Doberman Pinscher", .large, 32, 45),
        b("Shih Tzu", .small, 4, 7.3),
        b("Boston Terrier", .small, 5, 11.3),
        b("Bernese Mountain Dog", .giant, 36, 52),
        b("Pomeranian", .toy, 1.9, 3.5),
        b("Havanese", .small, 3, 6),
        b("Cane Corso", .giant, 40, 50),
        b("Miniature Schnauzer", .small, 5, 9),
        b("Shetland Sheepdog", .small, 6, 12),
        b("Chihuahua", .toy, 1.5, 3),
        b("Border Collie", .medium, 12, 20),
        b("Pug", .small, 6.3, 8.2),
        b("Mastiff (English)", .giant, 54, 100),
        b("Vizsla", .medium, 18, 30),
        b("Weimaraner", .large, 25, 40),
        b("Cocker Spaniel", .small, 7, 14),
        b("English Springer Spaniel", .medium, 18, 25),
        b("Basset Hound", .medium, 20, 29),
        b("Belgian Malinois", .large, 18, 34),
        b("Bullmastiff", .giant, 45, 59),
        b("Newfoundland", .giant, 45, 70),
        b("Rhodesian Ridgeback", .large, 29, 41),
        b("West Highland White Terrier", .small, 6.8, 9.1),
        b("Shiba Inu", .small, 6.8, 11),
        b("Bichon Frise", .small, 5, 8),
        b("Maltese", .toy, 1.8, 3.2),
        b("Great Pyrenees", .giant, 38, 73),
        b("Saint Bernard", .giant, 54, 82),
        b("Akita", .giant, 32, 59),
        b("Australian Cattle Dog", .medium, 15, 22),
        b("Whippet", .medium, 6.8, 14),
        b("Collie (Rough)", .large, 22, 34),
        b("Samoyed", .medium, 16, 30),
        b("Alaskan Malamute", .giant, 34, 45),
        b("Bloodhound", .giant, 40, 54),
        b("Portuguese Water Dog", .medium, 16, 27),
        b("Chow Chow", .medium, 20, 32),
        b("English Setter", .large, 20, 36),
        b("Brittany", .medium, 14, 18),
        b("Papillon", .toy, 2.3, 4.5),
        b("Staffordshire Bull Terrier", .small, 11, 17),
        b("American Staffordshire Terrier", .medium, 18, 30),
        b("Soft Coated Wheaten Terrier", .medium, 13.6, 18),
        b("Lhasa Apso", .small, 5.4, 8.2),
        b("Dalmatian", .medium, 16, 32),
        b("Irish Setter", .large, 25, 32),
        b("Old English Sheepdog", .giant, 27, 45),
    ]

    private static func b(_ name: String, _ size: DogSize, _ lo: Double, _ hi: Double) -> BreedInfo {
        BreedInfo(name: name, size: size, idealLoKg: lo, idealHiKg: hi)
    }

    /// Case-insensitive prefix/substring search, ranked so prefix matches win.
    static func search(_ query: String) -> [BreedInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        let hits = all.filter { $0.name.lowercased().contains(q) }
        return hits.sorted { lhs, rhs in
            let lp = lhs.name.lowercased().hasPrefix(q), rp = rhs.name.lowercased().hasPrefix(q)
            if lp != rp { return lp }
            return lhs.name < rhs.name
        }
    }

    static func find(_ name: String?) -> BreedInfo? {
        guard let name else { return nil }
        return all.first { $0.name == name }
    }
}
