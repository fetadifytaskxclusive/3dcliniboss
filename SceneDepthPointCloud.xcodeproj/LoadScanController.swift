//
//  LoadScanController.swift
//  SceneDepthPointCloud

import UIKit
import Foundation

class LoadScanController: UIViewController, UIPickerViewDelegate, UIPickerViewDataSource, UITableViewDelegate, UITableViewDataSource {
    private var savedScans = [URL]()
    private var selectedScan: URL?
    private var selectedScanIdx: Int?
    
    private let tableView = UITableView()
    private let loadButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let emptyStateLabel = UILabel()
    
    var mainController: MainController!
    var onScanLoaded: ((URL) -> Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        
        // Carregar escaneamentos salvos
        loadSavedScans()
        
        setupUI()
        setupConstraints()
    }
    
    private func setupUI() {
        // Título
        titleLabel.text = "Escaneamentos Salvos"
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        
        // TableView para listar escaneamentos
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(ScanTableViewCell.self, forCellReuseIdentifier: "ScanCell")
        tableView.backgroundColor = .clear
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        
        // Empty state
        emptyStateLabel.text = "📦\n\nNenhum escaneamento salvo ainda.\nFaça seu primeiro escaneamento!"
        emptyStateLabel.textColor = .secondaryLabel
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.numberOfLines = 0
        emptyStateLabel.font = .systemFont(ofSize: 16)
        emptyStateLabel.isHidden = !savedScans.isEmpty
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyStateLabel)
        
        // Botão Carregar
        loadButton.setTitle("Carregar Escaneamento", for: .normal)
        loadButton.setImage(UIImage(systemName: "arrow.down.circle.fill"), for: .normal)
        loadButton.tintColor = .systemGreen
        loadButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        loadButton.translatesAutoresizingMaskIntoConstraints = false
        loadButton.addTarget(self, action: #selector(loadSelectedScan), for: .touchUpInside)
        loadButton.isEnabled = false
        view.addSubview(loadButton)
        
        // Botão Cancelar
        cancelButton.setTitle("Cancelar", for: .normal)
        cancelButton.tintColor = .systemRed
        cancelButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(dismissModal), for: .touchUpInside)
        view.addSubview(cancelButton)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            tableView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            tableView.bottomAnchor.constraint(equalTo: loadButton.topAnchor, constant: -20),
            
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            
            loadButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            loadButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            loadButton.bottomAnchor.constraint(equalTo: cancelButton.topAnchor, constant: -12),
            loadButton.heightAnchor.constraint(equalToConstant: 50),
            
            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            cancelButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    private func loadSavedScans() {
        let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask)[0]
        savedScans = (try? FileManager.default.contentsOfDirectory(
            at: docs, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)) ?? []
        
        // Ordenar por data de criação (mais recente primeiro)
        savedScans.sort { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            return date1 > date2
        }
    }
    
    // MARK: - TableView DataSource & Delegate
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return savedScans.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ScanCell", for: indexPath) as! ScanTableViewCell
        let scanURL = savedScans[indexPath.row]
        cell.configure(with: scanURL)
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectedScan = savedScans[indexPath.row]
        selectedScanIdx = indexPath.row
        loadButton.isEnabled = true
        loadButton.tintColor = .systemGreen
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let scanToDelete = savedScans[indexPath.row]
            
            // Confirmar exclusão
            let alert = UIAlertController(
                title: "Excluir Escaneamento",
                message: "Tem certeza que deseja excluir '\(scanToDelete.lastPathComponent)'?",
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
            alert.addAction(UIAlertAction(title: "Excluir", style: .destructive) { _ in
                try? FileManager.default.removeItem(at: scanToDelete)
                self.savedScans.remove(at: indexPath.row)
                tableView.deleteRows(at: [indexPath], with: .fade)
                
                if self.savedScans.isEmpty {
                    self.emptyStateLabel.isHidden = false
                    self.loadButton.isEnabled = false
                }
                
                // Atualizar seleção
                if self.selectedScanIdx == indexPath.row {
                    self.selectedScan = nil
                    self.selectedScanIdx = nil
                    self.loadButton.isEnabled = false
                }
            })
            
            present(alert, animated: true)
        }
    }
    
    // MARK: - Actions
    
    @objc private func loadSelectedScan() {
        guard let scan = selectedScan else { return }
        
        // TODO: Implementar carregamento do arquivo PLY na cena
        // Por enquanto, apenas exportar/compartilhar
        dismissModal()
        onScanLoaded?(scan)
        
        // Ou exportar:
        // mainController.export(url: scan)
    }
    
    @objc private func dismissModal() {
        dismiss(animated: true, completion: nil)
    }
}

// MARK: - Custom TableView Cell

class ScanTableViewCell: UITableViewCell {
    private let iconImageView = UIImageView()
    private let nameLabel = UILabel()
    private let dateLabel = UILabel()
    private let sizeLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 12
        layer.masksToBounds = true
        
        // Ícone
        iconImageView.image = UIImage(systemName: "cube.fill")
        iconImageView.tintColor = .systemBlue
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconImageView)
        
        // Nome do arquivo
        nameLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = .label
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)
        
        // Data
        dateLabel.font = .systemFont(ofSize: 14)
        dateLabel.textColor = .secondaryLabel
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(dateLabel)
        
        // Tamanho
        sizeLabel.font = .systemFont(ofSize: 14)
        sizeLabel.textColor = .secondaryLabel
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sizeLabel)
        
        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 40),
            iconImageView.heightAnchor.constraint(equalToConstant: 40),
            
            nameLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            
            dateLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            dateLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            
            sizeLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            sizeLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 2)
        ])
    }
    
    func configure(with url: URL) {
        nameLabel.text = url.lastPathComponent
        
        // Data de criação
        if let resourceValues = try? url.resourceValues(forKeys: [.creationDateKey]),
           let creationDate = resourceValues.creationDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            dateLabel.text = formatter.string(from: creationDate)
        }
        
        // Tamanho do arquivo
        if let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let fileSize = resourceValues.fileSize {
            sizeLabel.text = ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
        }
    }
}
