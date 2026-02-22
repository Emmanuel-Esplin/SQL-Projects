Read me.md  
  
# Diamond Company – MySQL End‑to‑End (4Cs, ERD, Triggers, Procs, Views, Events)  
  
An end‑to‑end MySQL 8.0 project for a diamond manufacturing & sales workflow:  
- Models **GIA 4Cs** (Cut, Color, Clarity, Carat) as first‑class attributes.  
- Uses **InnoDB** with FKs, **CHECK** constraints, **triggers**, **stored procedures**, **views**, **JSON audit logs**, and the **Event Scheduler**.  
- Includes Mermaid **ERD** and **process flow** diagrams.  
  
## Quickstart  
```bash  
docker-compose up -d  
# wait for initialization  
mysql -h127.0.0.1 -uroot -prootpw -e "USE diamond_company; SHOW TABLES;"  
  
**Run a demo**  
See sql/02_seed_data.sql then try the test calls in the README:  
1. CALL sp_grade_diamond(...);  
2. CALL sp_place_order(...);  
3. CALL sp_fulfill_order(...);  
4. Query v_diamond_catalog, v_sales_by_month, v_inventory_value.  
**Diagrams**  
• diagrams/erd.mmd – ER diagram (rendered by GitHub)  
• diagrams/process-flow.mmd – end‑to‑end workflow  
**Notes on standards & docs**  
• **4Cs** (Cut, Color, Clarity, Carat) per GIA; Cut grade scale applies to round brilliants.  
References: GIA 4Cs overview and cut grade pages.  
• **MySQL 8.0** features used:  
    • InnoDB default + FKs  
    • CHECK constraints (≥ 8.0.16)  
    • CREATE TRIGGER  
    • CREATE PROCEDURE  
    • CREATE VIEW  
    • JSON data type  
    • CREATE EVENT + Event Scheduler  
