import UIKit
import DeepLinkNow

class ViewController: UIViewController {
    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 20
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "DeepLinkNow Example"
        label.font = .systemFont(ofSize: 24, weight: .bold)
        return label
    }()
    
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.text = "Waiting for deep links..."
        label.font = .systemFont(ofSize: 16)
        label.textColor = .gray
        label.numberOfLines = 0
        label.textAlignment = .center
        return label
    }()
    
    private let generateButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Generate Test Deep Link", for: .normal)
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        view.backgroundColor = .white
        
        view.addSubview(stackView)
        
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(statusLabel)
        stackView.addArrangedSubview(generateButton)
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])
        
        generateButton.addTarget(self, action: #selector(generateDeepLink), for: .touchUpInside)
    }
    
    func handleDeepLink(_ url: URL) {
        statusLabel.text = "Received deep link:\n\(url)"
    }
    
    @objc private func generateDeepLink() {
        // Create test parameters
        let customParams = DLNCustomParameters([
            "referrer": "example_app",
            "campaign": "test",
            "is_demo": true
        ])
        
        // Generate the deep link
        if let url = DeepLinkNow.createDeepLink(
            path: "/example/test",
            customParameters: customParams
        ) {
            statusLabel.text = "Generated deep link:\n\(url)"
        }
    }
} 