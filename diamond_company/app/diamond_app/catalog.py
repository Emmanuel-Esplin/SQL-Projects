"""Allowed values, mirroring the ENUMs in sql/01_schema.sql."""

SHAPES = ("Round", "Princess", "Cushion", "Oval", "Emerald", "Pear", "Marquise",
          "Radiant", "Asscher", "Heart", "Other")
ORIGINS = {"NATURAL": "Natural", "LAB_GROWN": "Lab-grown"}
COLOR_TYPES = {"WHITE": "White (D-Z)", "FANCY": "Fancy color"}
FANCY_INTENSITIES = ("Faint", "Very Light", "Light", "Fancy Light", "Fancy", "Fancy Intense",
                     "Fancy Vivid", "Fancy Deep", "Fancy Dark")
POLISH_STATES = {"UNPOLISHED": "Unpolished", "POLISHED": "Polished"}
CUT_GRADES = ("Excellent", "Very Good", "Good", "Fair", "Poor")
COLOR_GRADES = tuple("DEFGHIJKLMNOPQRSTUVWXYZ")
CLARITY_GRADES = ("FL", "IF", "VVS1", "VVS2", "VS1", "VS2", "SI1", "SI2", "I1", "I2", "I3")

STATUSES = {
    "AVAILABLE": "In stock",
    "IN_POLISHING": "In polishing",
    "IN_REPAIR": "In repair",
    "RESERVED": "Being sold",
    "SOLD": "Sold",
    "SPLIT": "Split",
}
PURPOSES = {"POLISHING": "Polishing", "REPAIR": "Repair", "VIEWING": "Viewing", "SALE": "Sale"}
ORDER_STATUSES = {"PENDING": "Pending", "PAID": "Paid", "SHIPPED": "Shipped", "CANCELLED": "Cancelled"}
CERT_LABS = ("GIA", "IGI", "HRD", "AGS", "Other")
