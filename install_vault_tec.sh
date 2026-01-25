#!/bin/bash

# Vault-Tec Interface Colors
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}"
echo "----------------------------------------------------------------"
echo "   ROBCO INDUSTRIES (TM) TERMLINK PROTOCOL"
echo "   SYSTEM: VAULT-TEC BMS AUTOMATION"
echo "   LANGUAGE: ENGLISH (EN-US)"
echo "   INITIALIZING INSTALLATION SEQUENCE..."
echo "----------------------------------------------------------------"
echo -e "${NC}"

# 1. Create Directory Structure
ROOT_DIR="Vault_Tec_BMS"
echo -e "${GREEN}[+] Excavating Vault sector: ${ROOT_DIR}...${NC}"
mkdir -p "$ROOT_DIR/config/packages/bms"
mkdir -p "$ROOT_DIR/config/custom_templates"

# 2. Generate 1_infrastructure.yaml
echo -e "${GREEN}[+] Flashing holotape: 1_infrastructure.yaml...${NC}"
cat << 'END_INFRA' > "$ROOT_DIR/config/packages/bms/1_infrastructure.yaml"
# -----------------------------------------------------------------------------
# BMS Package: Infrastructure
# Author:      Home Assistant Architect | JrX-Code
# Description: Input Booleans & Modbus Proxy Sensors
# -----------------------------------------------------------------------------

# 1. MASTER SWITCH
input_boolean:
  bms_automation:
    name: "BMS | Automation Master"
    icon: mdi:robot-industrial

# 2. MODBUS PROXY SENSOR
# Direct communication with FoxESS without 'input_number' middleman
template:
  - trigger:
      # Poll every 2 minutes (Reduces Modbus load)
      - trigger: time_pattern
        minutes: "/2"
      # Force update immediately on mode change
      - trigger: state
        entity_id: select.work_mode
    action:
      - action: foxess_modbus.read_registers
        data:
          start_address: 31038
          count: 1
          type: input
          inverter: 3f1f40c08ecfa1213be0afec436b3188
        response_variable: modbus_data
    sensor:
      - name: "Battery SoC Raw"
        unique_id: battery_soc_raw
        unit_of_measurement: "%"
        device_class: battery
        state_class: measurement
        state: >
          {% if modbus_data is defined and modbus_data['values'] is defined %}
            {{ modbus_data['values'][31038] | int }}
          {% else %}
            {# Fix for startup race condition #}
            {{ this.state | int(0) }}
          {% endif %}
END_INFRA

# 3. Generate 2_logic.yaml
echo -e "${GREEN}[+] Flashing holotape: 2_logic.yaml...${NC}"
cat << 'END_LOGIC' > "$ROOT_DIR/config/packages/bms/2_logic.yaml"
# -----------------------------------------------------------------------------
# BMS Package: Logic & Calculations
# Author:      Home Assistant Architect | JrX-Code
# Description: Template sensors calculating demand and charge start times.
# -----------------------------------------------------------------------------

template:
  # 1. PREDICTED DEMAND SENSOR
  - sensor:
      - name: "BMS Predicted Demand"
        unique_id: bms_predicted_demand
        unit_of_measurement: "kWh"
        state_class: measurement
        state: >
          {# 1. Calculate time difference between sunrise and 13:00 #}
          {% set next_rising = states('sensor.sun_next_rising') %}
          
          {# Fix for startup race condition #}
          {% if next_rising in ['unknown', 'unavailable', 'none'] %}
            0
          {% else %}
            {% set rising_local = next_rising | as_datetime | as_local %}
            {% set target_local = rising_local.replace(hour=13, minute=0, second=0, microsecond=0) %}
            
            {# Difference in hours #}
            {% set diff_hours = (target_local - rising_local).total_seconds() / 3600 %}
  
            {# 2. Season Factors (Keys must match Polish 'sensor.pora_roku') #}
            {% set season = states('sensor.pora_roku') | lower %}
            {% set factors = {
              'wiosna': 1.3,
              'lato': 1.0,
              'jesień': 1.3,
              'zima': 1.8
            } %}
  
            {# Select factor (default to 1.8/winter if undefined) #}
            {% set factor = factors.get(season, 1.8) %}
  
            {# Result: Predicted consumption in kWh #}
            {{ (diff_hours * factor) | round(2) }}
          {% endif %}

  # 2. START TIME SENSORS
  - sensor:
      - name: "BMS Start Time 06:00"
        unique_id: bms_start_time_06_00
        device_class: timestamp
        state: >
          {% from 'bms.jinja' import calculate_start_time %}
          {{ calculate_start_time(
              '06:00', 
              'sensor.solcast_pv_forecast_prognoza_na_dzisiaj', 
              states('sensor.battery_soc_raw')|float(0),
              states('sensor.bms_predicted_demand')|float(10) 
          ) }}

      - name: "BMS Start Time 15:00"
        unique_id: bms_start_time_15_00
        device_class: timestamp
        state: >
          {% from 'bms.jinja' import calculate_start_time %}
          {# Afternoon: Full charge (20kWh) #}
          {{ calculate_start_time(
              '15:00', 
              'sensor.solcast_pv_forecast_prognoza_na_dzisiaj', 
              states('sensor.battery_soc_raw')|float(0),
              20
          ) }}

  # 3. HYSTERESIS SWITCH
  - binary_sensor:
      - name: "BMS Charge Required"
        unique_id: bms_charge_required
        state: "{{ states('sensor.battery_soc_raw')|float(100) < 95 }}"
END_LOGIC

# 4. Generate bms.jinja (Logic Core)
echo -e "${GREEN}[+] Compiling logic core: bms.jinja...${NC}"
cat << 'END_JINJA' > "$ROOT_DIR/config/custom_templates/bms.jinja"
{% macro calculate_start_time(target_hour_str, forecast_entity, current_soc, predicted_demand_kwh) %}
  {# --------------------------------------------------- #}
  {# BMS CALCULATION ENGINE v1.2                         #}
  {# --------------------------------------------------- #}
  
  {% set capacity_kwh = 20 %}
  {% set charge_power_kw = 10 %}
  
  {# 1. TARGET CALCULATION #}
  {% set target_kwh = [predicted_demand_kwh, capacity_kwh] | min %}
  {% set current_kwh_in_battery = (current_soc / 100.0) * capacity_kwh %}
  {% set kwh_needed_gross = [0, target_kwh - current_kwh_in_battery] | max %}

  {# 2. ENVIRONMENTAL DATA #}
  {% set season = states('sensor.pora_roku') %}
  {% set weather = states('sensor.openweathermap_condition') %}
  {% set temp_c = states('sensor.openweathermap_temperature') | float(none) %}
  {% set raw_forecast = states(forecast_entity) | float(0) %}

  {# 3. MODIFIERS #}
  
  {# Season (Polish keys mapping) #}
  {% if season == 'zima' %} {% set season_mod = 0.7 %}
  {% elif season == 'jesień' %} {% set season_mod = 0.8 %}
  {% elif season == 'wiosna' %} {% set season_mod = 0.9 %}
  {% else %} {% set season_mod = 1.0 %} {% endif %}

  {# Weather #}
  {% if weather in ['cloudy', 'rainy', 'snowy', 'fog', 'mist', 'overcast', 'drizzle'] %}
    {% set weather_mod = 0.5 %}
  {% elif weather in ['partlycloudy', 'partly sunny'] %}
    {% set weather_mod = 0.7 %}
  {% elif weather in ['clear', 'sunny'] %}
    {% set weather_mod = 1.0 %}
  {% else %}
    {% set weather_mod = 0.8 %}
  {% endif %}

  {# Temperature PV Efficiency #}
  {% if temp_c is none %} {% set temp_pv_mod = 1.0 %}
  {% elif temp_c < -10 %} {% set temp_pv_mod = 0.85 %}
  {% elif temp_c < 0 %} {% set temp_pv_mod = 0.92 %}
  {% elif temp_c < 15 %} {% set temp_pv_mod = 1.0 %}
  {% elif temp_c < 30 %} {% set temp_pv_mod = 0.95 %}
  {% else %} {% set temp_pv_mod = 0.88 %} {% endif %}

  {# Demand Mod (Heat Pump Efficiency) #}
  {% if temp_c is none %} {% set demand_mod = 1.0 %}
  {% elif temp_c < -15 %} {% set demand_mod = 0.4 %}
  {% elif temp_c < -10 %} {% set demand_mod = 0.5 %}
  {% elif temp_c < -5 %} {% set demand_mod = 0.6 %}
  {% elif temp_c < 0 %} {% set demand_mod = 0.7 %}
  {% elif temp_c < 5 %} {% set demand_mod = 0.8 %}
  {% elif temp_c < 15 %} {% set demand_mod = 0.9 %}
  {% elif temp_c <= 25 %} {% set demand_mod = 1.0 %}
  {% elif temp_c <= 28 %} {% set demand_mod = 0.8 %}
  {% elif temp_c <= 32 %} {% set demand_mod = 0.6 %}
  {% else %} {% set demand_mod = 0.88 %} {% endif %}

  {# 4. FINAL CALCULATION #}
  {% set total_mod = season_mod * weather_mod * temp_pv_mod * demand_mod %}
  {% set adjusted_solar = raw_forecast * total_mod %}
  
  {% set grid_needed = [0, kwh_needed_gross - adjusted_solar] | max %}
  
  {# Add 10% buffer for charging inefficiency #}
  {% set minutes_needed = ((grid_needed / charge_power_kw) * 60 * 1.1) | round(0, 'ceil') | int %}

  {# Date Logic #}
  {% set target_dt = today_at(target_hour_str) %}
  
  {# If target hour passed, calculate for tomorrow #}
  {% if target_dt < now() %}
    {% set target_dt = target_dt + timedelta(days=1) %}
  {% endif %}

  {# RESULT #}
  {% if minutes_needed > 0 %}
    {{ (target_dt - timedelta(minutes=minutes_needed)).isoformat() }}
  {% else %}
    {# If no charge needed, push time to future to avoid triggering #}
    {{ (target_dt + timedelta(days=1)).isoformat() }}
  {% endif %}
{% endmacro %}
END_JINJA

# 5. Generate Automation Reference
echo -e "${GREEN}[+] Saving Automation protocols: automation_reference.yaml...${NC}"
cat << 'END_AUTO' > "$ROOT_DIR/automation_reference.yaml"
# -----------------------------------------------------------------------------
# AUTOMATION CODE (COPY TO GUI or automations.yaml)
# Version: 1.2.0 (English Aliases)
# -----------------------------------------------------------------------------

alias: BMS | Core Logic
description: "Core battery charging logic based on Jinja calculations. (v1.2.0)"
mode: restart

triggers:
  - alias: "🕒 START: Dynamic Calculated Time (06:00 or 15:00)"
    id: start_charge
    platform: template
    value_template: >
      {% set t6 = states('sensor.bms_start_time_06_00') | as_datetime %}
      {% set t15 = states('sensor.bms_start_time_15_00') | as_datetime %}
      {{ 
        (t6 is not none and now() >= t6) or 
        (t15 is not none and now() >= t15) 
      }}

  - alias: "🛑 STOP: Hard Stop Morning Tariff (06:00)"
    id: stop_charge
    platform: time
    at: "06:00:00"

  - alias: "🛑 STOP: Hard Stop Afternoon Tariff (15:00)"
    id: stop_charge
    platform: time
    at: "15:00:00"

conditions:
  # SAFETY KILL SWITCH
  - alias: "SAFETY CHECK: Is Master Switch ON?"
    condition: state
    entity_id: input_boolean.bms_automation
    state: "on"

actions:
  - choose:
      # --- SCENARIO 1: START CHARGING ---
      - alias: "🟢 EXECUTION: Start Charging (Force Charge)"
        conditions:
          - condition: trigger
            id: start_charge
          - alias: "Is charging actually required? (<95%)"
            condition: state
            entity_id: binary_sensor.bms_charge_required
            state: "on"
        sequence:
          - alias: "Inverter: Force Charge"
            action: select.select_option
            target:
              entity_id: select.work_mode
            data:
              option: Force Charge
          
          - alias: "Notification: Mobile App (Telefon)"
            action: notify.mobile_app_telefon_jarek_fold7
            data:
              title: "🚀 BMS Started"
              message: "Charging initiated. SoC: {{ states('sensor.battery_soc_raw') }}%"
              data:
                tag: bms_status
                group: bms_log
                channel: "BMS Alerts"

      # --- SCENARIO 2: STOP CHARGING ---
      - alias: "🔴 EXECUTION: Stop Charging (Self Use)"
        conditions:
          - condition: trigger
            id: stop_charge
        sequence:
          - alias: "Inverter: Self Use"
            action: select.select_option
            target:
              entity_id: select.work_mode
            data:
              option: Self Use
          
          - alias: "Notification: Mobile App (Telefon)"
            action: notify.mobile_app_telefon_jarek_fold7
            data:
              title: "✅ BMS Stopped"
              message: "Returned to Self Use. SoC: {{ states('sensor.battery_soc_raw') }}%"
              data:
                tag: bms_status
                group: bms_log
                channel: "BMS Alerts"
END_AUTO

# 6. Generate README (Safe Mode using echo to avoid delimiter issues)
echo -e "${GREEN}[+] Generating README documentation...${NC}"
echo "# Vault-Tec BMS Automation (v1.2.0)" > "$ROOT_DIR/README.md"
echo "" >> "$ROOT_DIR/README.md"
echo "Energy management system for Home Assistant. Inspired by post-apocalyptic efficiency." >> "$ROOT_DIR/README.md"
echo "" >> "$ROOT_DIR/README.md"
echo "## Structure" >> "$ROOT_DIR/README.md"
echo "- custom_templates/bms.jinja : The Brain" >> "$ROOT_DIR/README.md"
echo "- packages/bms/1_infrastructure.yaml : Switches & Modbus" >> "$ROOT_DIR/README.md"
echo "- packages/bms/2_logic.yaml : Logic Sensors" >> "$ROOT_DIR/README.md"
echo "- automation_reference.yaml : Automation Code" >> "$ROOT_DIR/README.md"
echo "" >> "$ROOT_DIR/README.md"
echo "## Installation" >> "$ROOT_DIR/README.md"
echo "1. Copy folders into HA config." >> "$ROOT_DIR/README.md"
echo "2. Add packages include in configuration.yaml." >> "$ROOT_DIR/README.md"
echo "3. Restart Home Assistant." >> "$ROOT_DIR/README.md"
echo "4. Create automation from reference file." >> "$ROOT_DIR/README.md"
echo "" >> "$ROOT_DIR/README.md"
echo "## Status" >> "$ROOT_DIR/README.md"
echo "- System: OPERATIONAL" >> "$ROOT_DIR/README.md"
echo "- Security: GREEN" >> "$ROOT_DIR/README.md"

echo -e "${GREEN}"
echo "----------------------------------------------------------------"
echo "   INSTALLATION COMPLETE."
echo "   DATA SAVED TO: $(pwd)/$ROOT_DIR"
echo "   PREPARE FOR THE FUTURE."
echo "----------------------------------------------------------------"
echo -e "${NC}"
