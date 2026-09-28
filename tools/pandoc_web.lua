-- Adapt Markdown links to the generated Web tree and use the first level-one
-- heading as the page title when the source has no YAML title.

function Link(element)
	local path, suffix = element.target:match("^(.-)%.md(.*)$")
	if path then
		element.target = path .. ".html" .. suffix
	end
	return element
end

function Pandoc(document)
	if document.meta.title == nil then
		for _, block in ipairs(document.blocks) do
			if block.t == "Header" and block.level == 1 then
				document.meta.title = pandoc.MetaInlines(block.content)
				break
			end
		end
	end
	return document
end
