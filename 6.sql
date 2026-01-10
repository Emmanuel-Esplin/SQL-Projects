""" Create a database schema """
DROP DATABASE IF EXISTS my_web_db;
CREATE DATABASE my_web_db CHARACTER SET utf8mb4;
USE my_web_db;

CREATE TABLE users (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100)
) ENGINE=InnoDB;

CREATE TABLE products (
    product_id INT AUTO_INCREMENT PRIMARY KEY,
    product_name VARCHAR(255) NOT NULL,
    description TEXT
) ENGINE=InnoDB;

CREATE TABLE downloads (
    download_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    product_id INT,
    download_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id),
    INDEX(user_id),
    INDEX(product_id)
) ENGINE=InnoDB;