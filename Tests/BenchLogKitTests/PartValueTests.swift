import Testing
@testable import BoardViewKit

// S-078: values read from the words around a part's name, laid out as on the A1502 schematic.
@Suite struct PartValueTests {
    private func word(_ text: String, _ minX: Double, _ minY: Double, _ maxX: Double, _ maxY: Double, page: Int = 0) -> SchematicWord {
        SchematicWord(text: text, page: page, minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    @Test(arguments: [
        (["22UF", "20%", "6.3V", "X5R-CERM-1", "603"], PartType.capacitor, "22 µF 20% 6.3 V X5R 0603"),
        (["1000PF", "10%", "16V", "X7R-1", "0201"], .capacitor, "1000 pF 10% 16 V X7R 0201"),
        (["0.0022UF", "10%", "50V", "X7R"], .capacitor, "2.2 nF 10% 50 V X7R"),
        (["33UF", "20%", "16V", "POLY"], .capacitor, "33 µF 20% 16 V POLY"),
        (["12PF", "5%", "25V", "NP0-C0G", "0201"], .capacitor, "12 pF 5% 25 V NP0 0201"),
        (["113K", "1%", "1/20W", "MF", "201"], .resistor, "113 kΩ 1% 1/20 W 0201"),
        (["0.002", "1%", "1W", "MF", "0612-SHORT"], .resistor, "0.002 Ω 1% 1 W 0612"),
        (["4K7", "5%"], .resistor, "4.7 kΩ 5%"),
        (["0", "5%", "1/16W", "MF-LF", "402"], .resistor, "0 Ω 5% 1/16 W 0402"),
        (["2.2UH-20%-2.0A-0.108OHM", "2520-SM"], .inductor, "2.2 µH 20% 2 A 2520"),
        (["120-OHM-25%-1.3A", "0402"], .inductor, "120 Ω 25% 1.3 A 0402"),
        (["FERR-470-OHM", "0402"], .ferriteBead, "470 Ω 0402"),
        (["ISL8009B", "DFN"], .chip, "ISL8009B DFN"),
        (["DMN5L06VK-7", "SOT563"], .transistor, "DMN5L06VK-7 SOT563"),
        (["152S1870", "TPS62180", "QFN"], .chip, "TPS62180 QFN"),
        (["12MHZ"], .crystal, "12 MHz"),
        (["SMC_SYS_KBDLED", "0201"], .resistor, "0201"),
    ] as [([String], PartType, String)])
    func attributeWordsParse(words: [String], type: PartType, summary: String) {
        #expect(PartValue.parse(words, type: type).summary == summary)
    }

    @Test func aDielectricIsOnlyACapacitorsAndAPowerOnlyAResistors() {
        #expect(PartValue.parse(["X5R", "1/16W"], type: .capacitor).power == nil)
        #expect(PartValue.parse(["X5R", "1/16W"], type: .resistor).dielectric == nil)
    }

    @Test func theColumnUnderANameIsItsValue() {
        // C7821 and C7825 side by side, each with its column.
        let words = [
            word("CRITICAL", 566.2, 602.3, 591.6, 607.1),
            word("C7821", 566.2, 595.0, 587.0, 601.3), word("22UF", 566.9, 590.4, 579.4, 595.0),
            word("20%", 567.4, 587.2, 573.6, 590.3), word("6.3V", 567.4, 584.3, 575.5, 587.4),
            word("X5R-CERM-1", 567.4, 580.7, 588.2, 583.8), word("603", 567.4, 577.3, 573.6, 580.4),
            word("C7825", 607.2, 591.7, 626.0, 598.2), word("1", 630.0, 591.7, 632.6, 598.2),
            word("47UF", 614.9, 586.8, 627.4, 591.4), word("20%", 620.9, 583.8, 627.1, 586.9),
            word("6.3V", 619.0, 580.7, 627.1, 583.8), word("X5R-CERM-1", 606.2, 577.3, 627.1, 580.4),
            word("603", 620.9, 574.0, 627.1, 577.1),
        ]
        let values = SchematicValues.read(words, partNames: ["C7821", "C7825"])
        #expect(values["C7821"]?.summary == "22 µF 20% 6.3 V X5R 0603")
        #expect(values["C7825"]?.summary == "47 µF 20% 6.3 V X5R 0603")
    }

    @Test func aPinNumberGluedToTheNameIsLeftOut() {
        let words = [word("R78201", 410.6, 559.3, 433.9, 566.3), word("113K", 418.8, 554.6, 431.3, 559.2),
                     word("1%", 420.0, 551.0, 426.0, 554.0)]
        #expect(SchematicValues.read(words, partNames: ["R7820"])["R7820"]?.summary == "113 kΩ 1%")
    }

    @Test func aSidewaysPartReadsItsRow() {
        // R1340 and R1341 stacked, each value right of its name, ratings under the row.
        let words = [
            word("R1340", 69.5, 76.9, 90.4, 83.1), word("100K", 100.7, 77.9, 113.4, 82.7),
            word("1", 122.4, 76.9, 124.6, 83.1), word("5%", 151.6, 73.5, 156.1, 76.9), word("1/20W", 165.2, 73.5, 177.0, 76.9),
            word("R1341", 69.5, 69.9, 90.4, 76.1), word("20K", 102.4, 71.0, 111.7, 75.8),
            word("5%", 151.6, 66.5, 156.1, 69.9), word("1/20W", 165.2, 66.5, 177.0, 69.9),
            word("75", 120.0, 70.0, 124.0, 72.9), // a page reference, smaller
        ]
        let values = SchematicValues.read(words, partNames: ["R1340", "R1341"])
        #expect(values["R1340"]?.summary == "100 kΩ 5% 1/20 W")
        #expect(values["R1341"]?.summary == "20 kΩ 5% 1/20 W")
    }

    @Test func thePageThatSaysTheMostWins() {
        let words = [word("U7820", 232.8, 631.5, 264.0, 640.8, page: 2), word("ISL8009B", 235.0, 627.3, 260.4, 632.1, page: 2),
                     word("DFN", 242.8, 622.0, 252.2, 626.8, page: 2),
                     word("U7820", 100, 100, 130, 108, page: 5)]
        let value = SchematicValues.read(words, partNames: ["U7820"])["U7820"]
        #expect(value?.summary == "ISL8009B DFN")
        #expect(value?.page == 2)
    }
}
