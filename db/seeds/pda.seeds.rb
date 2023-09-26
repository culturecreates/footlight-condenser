# rails db:seed:single SEED=pda

pages = [
  ["footlight:ecce377d-0058-49dd-a590-960ef7e94122","footlight:ecce377d-0058-49dd-a590-960ef7e94122", "fr","Person"],
  ["footlight:ab5267c5-fea6-4d51-89ec-7a1d9ebafa24","footlight:ab5267c5-fea6-4d51-89ec-7a1d9ebafa24", "fr","Person"],
  ["footlight:06bb54cf-25a8-4c98-899e-3b59f3e6e3b1","footlight:06bb54cf-25a8-4c98-899e-3b59f3e6e3b1", "fr","Place"],
  ["footlight:5f5e16ed-f227-4995-ad71-eb80b8baeb89","footlight:5f5e16ed-f227-4995-ad71-eb80b8baeb89", "fr","Place"],
  ["footlight:75a0d3b2-3d28-43fd-a6f8-9cbb094a8d88","footlight:75a0d3b2-3d28-43fd-a6f8-9cbb094a8d88", "fr","Place"],
  ["footlight:c801e370-9e4e-44eb-adab-6a70237548cf","footlight:c801e370-9e4e-44eb-adab-6a70237548cf", "fr","Organization"],
  ["footlight:7d141a69-ca87-445e-bf59-f0f3eb0f5476","footlight:7d141a69-ca87-445e-bf59-f0f3eb0f5476", "fr","Organization"],
  ["footlight:c4ad3fde-870c-4e11-9231-24fda90f7070","footlight:c4ad3fde-870c-4e11-9231-24fda90f7070", "fr","Organization"],
  ["footlight:d414daa2-02d1-4881-999e-191b0fb4f9e8","footlight:d414daa2-02d1-4881-999e-191b0fb4f9e8", "fr","Organization"],
  ["footlight:4656ddf1-9412-4316-ae4c-ba1f36c34f62","footlight:4656ddf1-9412-4316-ae4c-ba1f36c34f62", "fr","Organization"],
  ["footlight:653bc24f-a49d-478c-b70c-b568cf5316ad","footlight:653bc24f-a49d-478c-b70c-b568cf5316ad", "fr","Organization"],
  ["footlight:7ba060da-c4d5-43ac-a622-4d711ac4b1e2","footlight:7ba060da-c4d5-43ac-a622-4d711ac4b1e2", "fr","Organization"],
  ["footlight:9783a7b0-09a8-4cec-9597-36791a924a64","footlight:9783a7b0-09a8-4cec-9597-36791a924a64", "fr","Organization"],
  ["footlight:b1b5d5ab-852a-4765-b5a2-375b225b7fe0","footlight:b1b5d5ab-852a-4765-b5a2-375b225b7fe0", "fr","Organization"]
]
site = Website.where(seedurl: "placedesarts-com").first

pages.each do |page|
  Webpage.create!(url: page[0], rdf_uri: page[1], language: page[2], website: site, rdfs_class: RdfsClass.where(name: page[3]).first)
end


