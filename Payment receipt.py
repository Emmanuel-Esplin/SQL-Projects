# Import packages
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet


# Data for the receipt
data = [
    ["Date", "Name", "Subsciption", "Amount"],
    ["2024-06-15", "John Doe", "Premium Plan", "$49.99"],
    ["2024-07-15", "Jane Smith", "Basic Plan", "$19.99"],
    ["Subtotal", "", "", "$69.98"],
    ["Tax (10%)", "", "", "$7.00"],
    ["Total", "", "", "$76.98"], 
]

# Create PDF document
pdf_file = "payment_receipt.pdf"
document = SimpleDocTemplate(pdf_file, pagesize=A4)
styles = getSampleStyleSheet()
elements = []

# Title
title = Paragraph("Payment Receipt", styles["Title"])
elements.append(title)
elements.append(Spacer(1, 12))

# Create table
table = Table(data)
table.setStyle(TableStyle([
    ('BACKGROUND', (0, 0), (-1, 0), colors.grey),
    ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
    ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
    ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
    ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
    ('BACKGROUND', (0, 1), (-1, -1), colors.beige),
    ('GRID', (0, 0), (-1, -1), 1, colors.black),
]))
elements.append(table)
elements.append(Spacer(1, 12))

# Footer 
footer = Paragraph("Thank you for your payment!", styles["Normal"])
elements.append(footer)

# Build PDF
document.build(elements)
print(f"Payment receipt generated: {pdf_file}")

