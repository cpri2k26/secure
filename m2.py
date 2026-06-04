#!/usr/bin/env python3
import sys
import os
import socket
import threading
import json

from PyQt6.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, 
                             QHBoxLayout, QLabel, QLineEdit, QPushButton, \
                             QComboBox, QSystemTrayIcon, QListWidget, QListWidgetItem, QMenu)
from PyQt6.QtCore import Qt, pyqtSignal
from PyQt6.QtGui import QIcon, QPixmap, QColor, QFont

# Cryptography imports
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

START_PORT = 61234          
SUBNET_BASE = "172."  

# ==========================================
# 1. THE STATE DIRECTORY CLASS (Data Layer)
# ==========================================
class PeerDirectory:
    """
    Manages contact identities cleanly. It ensures identity resolution and 
    deduplication by forcing IP:Port to be the absolute, immutable key, 
    while hostnames remain fluid properties.
    """
    def __init__(self):
        self._peers = {} # Hidden master storage

    def register_or_update(self, ip, port, hostname=None):
        unique_key = f"{ip}:{port}"
        if unique_key not in self._peers:
            self._peers[unique_key] = {
                "ip": ip,
                "port": port,
                "hostname": hostname or "User"
            }
        else:
            # Identity Resolution: If the connection exists, update name without duplicating
            if hostname and hostname != "Unknown":
                self._peers[unique_key]["hostname"] = hostname
        return unique_key

    def get_display_name(self, unique_key):
        if unique_key in self._peers:
            p = self._peers[unique_key]
            return f"{p['hostname']} ({p['ip']}:{p['port']})"
        return unique_key

    def get_coordinates(self, unique_key):
        if unique_key in self._peers:
            return self._peers[unique_key]["ip"], self._peers[unique_key]["port"]
        return None

    def all_keys(self):
        return list(self._peers.keys())


# ==========================================
# 2. MAIN APPLICATION CLASS (UI/Network Layer)
# ==========================================
class ModernSecureChatApp(QMainWindow):
    append_signal = pyqtSignal(str, str, bool) # unique_key, text, is_sent
    update_peers_signal = pyqtSignal()
    notification_signal = pyqtSignal(str, str) 
    update_title_signal = pyqtSignal(str)      

    def __init__(self):
        super().__init__()
        
        # Initialize our dedicated state directory component
        self.directory = PeerDirectory()
        
        # Cryptographic and history containers now cleanly index by unique network keys
        self.chat_histories = {} 
        self.my_outbound_aes_keys = {}  
        self.peer_inbound_aes_keys = {} 
        self.my_active_port = START_PORT
        
        # Cryptography Setup
        self.private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        self.public_key = self.private_key.public_key()
        self.public_pem = self.public_key.public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo
        )

        # Hook signals
        self.append_signal.connect(self.safe_append_to_history)
        self.update_peers_signal.connect(self.safe_update_dropdown)
        self.notification_signal.connect(self.safe_show_notification)
        
        self.init_ui()
        self.update_title_signal.connect(self.title_label.setText) 
        
        self.setup_tray_icon()
        threading.Thread(target=self.start_universal_listener, daemon=True).start()
        self.old_pos = None

    def init_ui(self):
        self.setWindowFlags(Qt.WindowType.FramelessWindowHint | Qt.WindowType.WindowStaysOnTopHint)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.resize(360, 550)

        screen = QApplication.primaryScreen().geometry()
        self.move(screen.width() - self.width() - 20, screen.height() - self.height() - 60)

        main_widget = QWidget(self)
        self.setCentralWidget(main_widget)
        main_widget.setObjectName("MainContainer")
        
        self.setStyleSheet("""
            #MainContainer { background-color: #121212; border-radius: 12px; border: 1px solid #333333; }
            QLabel { font-family: Arial; color: #ffffff; }
            QLineEdit, QComboBox { font-family: Arial; border: 1px solid #444444; border-radius: 6px; padding: 4px; background-color: #1e1e1e; color: #ffffff; }
            QComboBox QAbstractItemView { background-color: #1e1e1e; color: #ffffff; selection-background-color: #10b981; }
            QPushButton { background-color: #10b981; color: white; font-weight: bold; border-radius: 6px; padding: 6px 12px; }
            QPushButton:hover { background-color: #059669; }
            QPushButton#CloseBtn { background-color: transparent; color: #94a3b8; font-size: 14px; }
            QPushButton#CloseBtn:hover { color: #ffffff; background-color: #ef4444; }
            QListWidget { background-color: #121212; border: 1px solid #333333; border-radius: 6px; outline: none; }
            QScrollBar:vertical { background: #1e1e1e; width: 10px; }
            QScrollBar::handle:vertical { background: #555555; border-radius: 5px; }
        """)

        layout = QVBoxLayout(main_widget)
        
        # Header block
        header_layout = QHBoxLayout()
        self.title_label = QLabel("Chat (Initializing...)")
        self.title_label.setFont(QFont("Arial", 11, QFont.Weight.Bold))
        close_btn = QPushButton("✕")
        close_btn.setObjectName("CloseBtn")
        close_btn.setFixedSize(30, 30)
        close_btn.clicked.connect(self.hide) 
        header_layout.addWidget(self.title_label)
        header_layout.addStretch()
        header_layout.addWidget(close_btn)
        layout.addLayout(header_layout)

        self.title_label.mousePressEvent = self.header_mouse_press
        self.title_label.mouseMoveEvent = self.header_mouse_move

        # Connection Scanner Engine input
        target_layout = QHBoxLayout()
        self.ip_entry = QLineEdit("1")
        self.ip_entry.setFixedWidth(50)
        connect_btn = QPushButton("Connect")
        connect_btn.clicked.connect(self.initiate_manual_connection)
        target_layout.addWidget(self.ip_entry)
        target_layout.addStretch()
        target_layout.addWidget(connect_btn)
        layout.addLayout(target_layout)

        # Peer Dropdown Box
        peer_layout = QHBoxLayout()
        self.peer_combo = QComboBox()
        self.peer_combo.currentIndexChanged.connect(self.on_peer_changed)
        peer_layout.addWidget(self.peer_combo, 1)
        layout.addLayout(peer_layout)

        # Chat Bubble Stream Frame
        self.chat_area = QListWidget()
        self.chat_area.setSelectionMode(QListWidget.SelectionMode.NoSelection)
        layout.addWidget(self.chat_area)

        # Input and sending tray
        input_layout = QHBoxLayout()
        self.msg_entry = QLineEdit()
        self.msg_entry.returnPressed.connect(self.send_message)
        send_btn = QPushButton("Send")
        send_btn.clicked.connect(self.send_message)
        input_layout.addWidget(self.msg_entry)
        input_layout.addWidget(send_btn)
        layout.addLayout(input_layout)

        self.hide()

    def setup_tray_icon(self):
        self.tray_icon = QSystemTrayIcon(self)
        pixmap = QPixmap(64, 64)
        pixmap.fill(QColor("#10b981"))
        self.tray_icon.setIcon(QIcon(pixmap))
        tray_menu = QMenu()
        tray_menu.addAction("Open Chat").triggered.connect(self.show_window)
        tray_menu.addAction("Exit").triggered.connect(QApplication.instance().quit)
        self.tray_icon.setContextMenu(tray_menu)
        self.tray_icon.activated.connect(lambda r: self.show_window() if r == QSystemTrayIcon.ActivationReason.DoubleClick else None)
        self.tray_icon.show()

    def show_window(self):
        self.show()
        self.activateWindow()
        self.msg_entry.setFocus()

    def header_mouse_press(self, event):
        if event.button() == Qt.MouseButton.LeftButton: self.old_pos = event.globalPosition().toPoint()

    def header_mouse_move(self, event):
        if self.old_pos is not None:
            delta = event.globalPosition().toPoint() - self.old_pos
            self.move(self.pos() + delta)
            self.old_pos = event.globalPosition().toPoint()

    def _add_bubble_to_ui(self, text, is_sent):
        row_widget = QWidget()
        row_layout = QHBoxLayout(row_widget)
        row_layout.setContentsMargins(5, 5, 5, 5)

        lbl = QLabel(text)
        lbl.setWordWrap(True)
        lbl.setMaximumWidth(int(self.chat_area.width() * 0.75)) 

        if is_sent:
            lbl.setStyleSheet("background-color: #10b981; color: white; padding: 8px; border-radius: 10px;")
            row_layout.addStretch()
            row_layout.addWidget(lbl)
        else:
            lbl.setStyleSheet("background-color: #333333; color: white; padding: 8px; border-radius: 10px;")
            row_layout.addWidget(lbl)
            row_layout.addStretch()

        item = QListWidgetItem(self.chat_area)
        item.setSizeHint(row_widget.sizeHint())
        self.chat_area.addItem(item)
        self.chat_area.setItemWidget(item, row_widget)
        self.chat_area.scrollToBottom()

    def on_peer_changed(self):
        self.chat_area.clear()
        # secretly read the unified IP:Port key stored beneath the text string
        selected_key = self.peer_combo.currentData()
        if selected_key and selected_key in self.chat_histories:
            for text, is_sent in self.chat_histories[selected_key]:
                self._add_bubble_to_ui(text, is_sent)

    def safe_update_dropdown(self):
        # Save current underlying network key selection before clearing items
        current_key = self.peer_combo.currentData()
        
        self.peer_combo.blockSignals(True)
        self.peer_combo.clear()
        
        all_keys = self.directory.all_keys()
        if not all_keys:
            self.peer_combo.addItem("No active targets", None)
        else:
            for key in all_keys:
                nice_name = self.directory.get_display_name(key)
                # Display the friendly string, but bind the unglitchable raw key inside
                self.peer_combo.addItem(nice_name, key)
        
        # Find index using the invariant key data layer
        index = -1
        for i in range(self.peer_combo.count()):
            if self.peer_combo.itemData(i) == current_key:
                index = i
                break
        
        if index >= 0:
            self.peer_combo.setCurrentIndex(index)
        else:
            self.peer_combo.setCurrentIndex(0)
            
        self.peer_combo.blockSignals(False)
        self.on_peer_changed()

    def safe_append_to_history(self, unique_key, text_line, is_sent):
        if unique_key not in self.chat_histories:
            self.chat_histories[unique_key] = []
        self.chat_histories[unique_key].append((text_line, is_sent))
        
        if self.peer_combo.currentData() == unique_key:
            self._add_bubble_to_ui(text_line, is_sent)

    def safe_show_notification(self, title, message):
        self.tray_icon.showMessage(title, message, QSystemTrayIcon.MessageIcon.Information, 4000)

    # --- Secure Background Network System ---
    def start_universal_listener(self):
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        port = START_PORT
        while True:
            try:
                server.bind(('0.0.0.0', port))
                self.my_active_port = port
                break
            except OSError:
                port += 1
        
        server.listen(10)
        self.update_title_signal.emit(f"Chat (Port: {self.my_active_port})")

        while True:
            try:
                conn, addr = server.accept()
                data = conn.recv(8192).decode('utf-8')
                if not data:
                    conn.close()
                    continue

                payload = json.loads(data)
                msg_type = payload.get("type")
                sender_hostname = payload.get("sender", "Unknown")
                sender_ip = addr[0]
                sender_port = payload.get("listening_port", START_PORT)

                # Deduplicate and register cleanly through the State Directory Class
                peer_key = self.directory.register_or_update(sender_ip, sender_port, sender_hostname)
                self.update_peers_signal.emit()

                if msg_type == "handshake_request":
                    conn.sendall(self.public_pem)

                elif msg_type == "handshake_key":
                    encrypted_aes_key = bytes.fromhex(payload.get("key"))
                    decrypted_aes_key = self.private_key.decrypt(
                        encrypted_aes_key,
                        padding.OAEP(mgf=padding.MGF1(algorithm=hashes.SHA256()), algorithm=hashes.SHA256(), label=None)
                    )
                    self.peer_inbound_aes_keys[peer_key] = decrypted_aes_key
                    threading.Thread(target=self.silent_return_handshake, args=(sender_ip, sender_port, peer_key), daemon=True).start()

                elif msg_type == "chat_msg":
                    if peer_key in self.peer_inbound_aes_keys:
                        nonce = bytes.fromhex(payload.get("nonce"))
                        ciphertext = bytes.fromhex(payload.get("ciphertext"))
                        aesgcm = AESGCM(self.peer_inbound_aes_keys[peer_key])
                        decrypted_msg = aesgcm.decrypt(nonce, ciphertext, None).decode('utf-8')
                        
                        self.append_signal.emit(peer_key, decrypted_msg, False)
                        self.notification_signal.emit(f"Message from {sender_hostname}", decrypted_msg)

                conn.close()
            except Exception:
                pass

    def silent_return_handshake(self, target_ip, target_port, peer_key):
        if peer_key in self.my_outbound_aes_keys: return
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(3.0)
            s.connect((target_ip, target_port))
            s.sendall(json.dumps({"type": "handshake_request", "sender": socket.gethostname(), "listening_port": self.my_active_port}).encode('utf-8'))
            response = s.recv(2048)
            peer_public_key = serialization.load_pem_public_key(response)
            
            new_aes_key = AESGCM.generate_key(bit_length=256)
            encrypted_aes_key = peer_public_key.encrypt(new_aes_key, padding.OAEP(mgf=padding.MGF1(algorithm=hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
            
            s2 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s2.connect((target_ip, target_port))
            s2.sendall(json.dumps({"type": "handshake_key", "sender": socket.gethostname(), "listening_port": self.my_active_port, "key": encrypted_aes_key.hex()}).encode('utf-8'))
            s2.close()
            s.close()
            self.my_outbound_aes_keys[peer_key] = new_aes_key
        except Exception: pass

    def initiate_manual_connection(self):
        host_x = self.ip_entry.text().strip()
        if not host_x: return
        target_ip = f"{SUBNET_BASE}{host_x}"
        threading.Thread(target=self.scan_and_handshake, args=(target_ip,), daemon=True).start()

    def scan_and_handshake(self, target_ip):
        for target_port in range(START_PORT, START_PORT + 6):
            try:
                s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                s.settimeout(0.5)
                s.connect((target_ip, target_port))
                s.sendall(json.dumps({"type": "handshake_request", "sender": socket.gethostname(), "listening_port": self.my_active_port}).encode('utf-8'))
                response = s.recv(2048)
                peer_public_key = serialization.load_pem_public_key(response)
                
                peer_key = self.directory.register_or_update(target_ip, target_port, "User")
                
                new_aes_key = AESGCM.generate_key(bit_length=256)
                encrypted_aes_key = peer_public_key.encrypt(new_aes_key, padding.OAEP(mgf=padding.MGF1(algorithm=hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
                
                s2 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                s2.connect((target_ip, target_port))
                s2.sendall(json.dumps({"type": "handshake_key", "sender": socket.gethostname(), "listening_port": self.my_active_port, "key": encrypted_aes_key.hex()}).encode('utf-8'))
                s2.close()
                s.close()
                
                self.my_outbound_aes_keys[peer_key] = new_aes_key
                self.update_peers_signal.emit()
                self.append_signal.emit(peer_key, "System: Secure connection verified.", False)
                break
            except: continue

    def send_message(self):
        peer_key = self.peer_combo.currentData()
        msg = self.msg_entry.text().strip()
        if not msg or not peer_key or peer_key not in self.my_outbound_aes_keys: return

        target_ip, target_port = self.directory.get_coordinates(peer_key)
        try:
            aesgcm = AESGCM(self.my_outbound_aes_keys[peer_key])
            nonce = os.urandom(12)
            ciphertext = aesgcm.encrypt(nonce, msg.encode('utf-8'), None)
            
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(3.0)
            s.connect((target_ip, target_port))
            s.sendall(json.dumps({"type": "chat_msg", "sender": socket.gethostname(), "listening_port": self.my_active_port, "nonce": nonce.hex(), "ciphertext": ciphertext.hex()}).encode('utf-8'))
            s.close()
            
            self.append_signal.emit(peer_key, msg, True)
            self.msg_entry.clear()
        except Exception as e:
            self.append_signal.emit(peer_key, f"System: Error: {e}", False)

if __name__ == "__main__":
    app = QApplication(sys.argv)
    QApplication.setQuitOnLastWindowClosed(False)
    window = ModernSecureChatApp()
    sys.exit(app.exec())