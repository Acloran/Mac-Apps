import AppKit

final class SliderMenuItemView: NSView {
    private let valueLabel = NSTextField(labelWithString: "")
    private let slider = NSSlider()
    private let formatter: (Double) -> String
    private let onChange: (Double) -> Void

    init(
        title: String,
        value: Double,
        minValue: Double,
        maxValue: Double,
        formatter: @escaping (Double) -> String,
        onChange: @escaping (Double) -> Void
    ) {
        self.formatter = formatter
        self.onChange = onChange

        super.init(frame: CGRect(x: 0, y: 0, width: 300, height: 44))

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.frame = CGRect(x: 14, y: 25, width: 190, height: 16)
        addSubview(titleLabel)

        valueLabel.alignment = .right
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.frame = CGRect(x: 210, y: 25, width: 74, height: 16)
        addSubview(valueLabel)

        slider.minValue = minValue
        slider.maxValue = maxValue
        slider.doubleValue = value
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged(_:))
        slider.frame = CGRect(x: 12, y: 3, width: 276, height: 22)
        addSubview(slider)

        updateValueLabel()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        updateValueLabel()
        onChange(sender.doubleValue)
    }

    private func updateValueLabel() {
        valueLabel.stringValue = formatter(slider.doubleValue)
    }
}

enum MenuValueFormatter {
    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
