
# Import necessary libraries
import pandas as pd
import plotly.graph_objects as go

# Define your budget data
budget_data = {
    'Category': ['3D Assets + Texturing', '2D Assets for UI', 'Level Designer', 'Sound Designer', 'Programmer', 'Marketing', 'QA Testers'],
    'Amount': [3000, 1500, 2000, 1000, 2500, 1500, 800]
}

# Create a DataFrame
df = pd.DataFrame(budget_data)

# Create the 3D pie chart using Plotly
fig = go.Figure(go.Pie(
    labels=df['Category'],
    values=df['Amount'],
    hole=0.3,  # to create a donut chart for better visualization
    pull=[0.1] * len(df),  # Pull each slice out slightly
    marker=dict(colors=plotly.colors.qualitative.Plotly)
))

# Update layout for 3D effect
fig.update_traces(textposition='inside', textinfo='percent+label')

fig.update_layout(
    title_text="Roblox Game Development Budget Distribution",
    annotations=[dict(text='Budget', x=0.5, y=0.5, font_size=20, showarrow=False)]
)

# Show the figure
fig.show()
