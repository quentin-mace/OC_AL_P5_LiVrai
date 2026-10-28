package com.livrai.dao;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;

public class AbstractDao {

    private Connection connection;

    private Connection getConnection() {
        if (connection == null) {
            loadDatabase();
        }
        return connection;
    }

    protected <T> T execute(SqlQuery<T> query) {
        try {
            return query.execute(getConnection());
        } catch (SQLException e) {
            throw new RuntimeException(e);
        }
    }

    protected void loadDatabase() {
        try {
            Class.forName("com.mysql.cj.jdbc.Driver");
        } catch (ClassNotFoundException e) {
        }

        String url = "jdbc:mysql://" + env("DB_HOST", "localhost") + ":" + env("DB_PORT", "3306")
                + "/" + env("DB_NAME", "livrai");

        try {
            connection = DriverManager.getConnection(url, env("DB_USER", "root"), env("DB_PASSWORD", "password"));
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

    private static String env(String name, String defaultValue) {
        String value = System.getenv(name);
        return value == null || value.isEmpty() ? defaultValue : value;
    }

    protected interface SqlQuery<T> {
        T execute(Connection connection) throws SQLException;
    }

}
