**Entity‑Relationship Diagram (ERD)**  
erDiagram  
    SUPPLIERS ||--o{ ROUGH_STONES : provides  
    ROUGH_STONES ||--o{ WORK_ORDERS : processed_by  
    EMPLOYEES ||--o{ WORK_ORDERS : assigned_to  
    ROUGH_STONES ||--o{ DIAMONDS : yields  
    DIAMONDS ||--o{ ORDER_ITEMS : sold_as  
    CUSTOMERS ||--o{ ORDERS : places  
    ORDERS ||--o{ ORDER_ITEMS : contains  
    DIAMONDS ||--o{ AUDIT_LOG : changes_recorded  
    DIAMONDS {  
      int diamond_id PK  
      varchar sku UK  
      int rough_id FK  
      decimal carat  
      enum cut_grade  
      enum color_grade  
      enum clarity_grade  
      decimal price_usd  
      enum status "AVAILABLE|RESERVED|SOLD"  
      boolean certified  
      varchar certification_number  
      datetime created_at  
      datetime updated_at  
    }  
    ROUGH_STONES {  
      int rough_id PK  
      int supplier_id FK  
      date received_date  
      decimal weight_carat  
      decimal cost_usd  
      enum status "RECEIVED|ASSIGNED|CUT|REJECTED"  
    }  
    WORK_ORDERS {  
      int work_order_id PK  
      int rough_id FK  
      int employee_id FK  
      date start_date  
      enum status "OPEN|IN_PROGRESS|DONE|CANCELLED"  
    }  
    CUT_FACTORS {  
      varchar grade PK  
      decimal multiplier  
    }  
    COLOR_FACTORS {  
      varchar grade PK  
      decimal multiplier  
    }  
    CLARITY_FACTORS {  
      varchar grade PK  
      decimal multiplier  
    }  
    ORDERS {  
      int order_id PK  
      int customer_id FK  
      date order_date  
      enum status "PENDING|PAID|SHIPPED|CANCELLED"  
    }  
    ORDER_ITEMS {  
      int order_item_id PK  
      int order_id FK  
      int diamond_id FK UK  
      decimal price_at_sale  
    }  
    AUDIT_LOG {  
      bigint audit_id PK  
      varchar table_name  
      varchar action  
      int row_id  
      json payload  
      datetime changed_at  
    }  
