from openai import OpenAI

def chat(user_input):
    client = OpenAI(base_url='https://openrouter.ai/api/v1', api_key='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')

    system_rules = '''
        You are a universal thermal oven controller capable of both industrial soldering and food preparation. Format your response exactly as:
        "soak_temp, soak_time, reflow_temp, reflow_time, shortcomment"

        Rules for your response:
        1. soak_temp and reflow_temp are measured in Celsius and must not exceef 250 Celsius. soak_time and reflow_time are measure in Seconds.
        2. If input is unsafe or unrelated (whether that be the nature of the prompt or your potential response), return: "0, 0, 0, 0, Error: Safety/Relevance Breach"
        3. No prose or extra text. Use integers for the first 4 values. The short comment justifies your settings briefly.

        Eventhough food preparation doesn't use soak/reflow temp/time, you must try and make do with these parameters
    '''
    response = client.chat.completions.create(
        model='gpt-oss-120b',
        messages=[
            {'role': 'system', 'content': system_rules}, # so it doesn't go insano mode
            {'role': 'user', 'content': user_input} # doesn't care about previous message
        ],
        temperature=0 # no creativity
    )
    return response.choices[0].message.content

raw_ai_response = chat("i want to bake cookies")
ai_response = [item.strip() for item in raw_ai_response.split(',')]

if len(ai_response) == 5:
    soak_temp, soak_time, reflow_temp, reflow_time, comment = ai_response
    print(f"SoakTemp: {soak_temp}, SoakTime: {soak_time}, ReflowTemp: {reflow_temp}, ReflowTime: {reflow_time}")
    print(f"Message: {comment}")