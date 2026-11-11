import Testing
@testable import BoardViewKit

// S-077
@Suite struct BoardNamesTests {
    @Test(arguments: [
        ("C713", PartType.capacitor), ("R5120", .resistor), ("RP1", .resistorNetwork), ("RN3", .resistorNetwork),
        ("L7130", .inductor), ("FB7101", .ferriteBead), ("FL2", .ferriteBead), ("U7000", .chip), ("IC5", .chip),
        ("Q7055", .transistor), ("D7101", .diode), ("CR2", .diode), ("LED1", .led), ("F7000", .fuse),
        ("J9000", .connector), ("CN1", .connector), ("Y5110", .crystal), ("X1", .crystal), ("OSC1", .oscillator),
        ("SW1", .switchPart), ("TP12", .testPoint), ("PP7801", .testPoint), ("XW7000", .jumper), ("T1", .transformer),
        ("c12", .capacitor), ("PPA400", .testPoint), ("DZ6601", .diode),
    ])
    func aPartsLettersGiveItsType(name: String, type: PartType) {
        #expect(PartType(partName: name) == type)
    }

    @Test(arguments: ["MH1", "ZZ9", "U", "C", "BRD", "", "7C"])
    func otherNamesSayNothing(name: String) {
        #expect(PartType(partName: name) == nil)
    }

    @Test(arguments: [
        ("PP3V3_S0", 3.3, "S0"), ("PP1V05_S0", 1.05, "S0"), ("PP0V9_S3", 0.9, "S3"), ("PP5V_S4SW", 5.0, "S4"),
        ("+1.8V_RUN", 1.8, "RUN"), ("PP12V_G3H", 12.0, "G3H"), ("VCC1P8_S5", 1.8, "S5"), ("PP3V42_G3H", 3.42, "G3H"),
        ("P3V3", 3.3, nil), ("+5VALW", 5.0, nil), ("PP1V8", 1.8, nil), ("PP20V_USBC_XA_VBUS", 20.0, nil),
    ] as [(String, Double, String?)])
    func aNetsNameGivesItsVoltageAndState(name: String, volts: Double, state: String?) {
        let info = NetInfo(netName: name)
        #expect(info.volts == volts)
        #expect(info.state == state)
        #expect(!info.isGround)
    }

    @Test(arguments: ["PPBUS_G3H", "PPDCIN_G3H", "USB_DP", "I2C_SMC_SDA", "P3V3S0_EN", "PP1V8_S0_PGOOD",
                      "SMC_PM_G2_EN", "PCIE_CLK100M_P", "LCD_BKLT_PWM", "V1P8A_X"])
    func namesWithoutAVoltageSayNone(name: String) {
        #expect(NetInfo(netName: name).volts == nil)
    }

    @Test func groundIsGround() {
        #expect(NetInfo(netName: "GND").isGround)
        #expect(NetInfo(netName: "GND_AUDIO").isGround)
        #expect(NetInfo(netName: "PPBUS_G3H").state == "G3H")
        #expect(NetInfo(netName: "PPBUS_G3H").isAlwaysOn)
    }
}
